package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var username string
var uid, gid int
var creds syscall.Credential

func setupUser(name string) {
	u, err := user.Lookup(name)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	uid = naturalNumber(u.Uid)
	gid = naturalNumber(u.Gid)

	creds.Uid = uint32(uid)
	creds.Gid = uint32(gid)
	creds.Groups = []uint32{creds.Gid}
}

type cmdError struct {
	cmd            string
	stdout, stderr []byte
	err            error
}

func (e *cmdError) Error() string {
	var sb bytes.Buffer

	fmt.Fprintf(&sb, "Command: %s\n", e.cmd)
	fmt.Fprintf(&sb, "Error: %v\n", e.err)

	if e.stdout != nil {
		fmt.Fprintln(&sb, "Stdout:")
		fmt.Fprint(&sb, string(e.stdout))
		fmt.Fprintln(&sb, "")
	}

	if e.stderr != nil {
		fmt.Fprintln(&sb, "Stderr:")
		fmt.Fprint(&sb, string(e.stderr))
		fmt.Fprintln(&sb, "")
	}

	return string(sb.Bytes())
}

func runCmdWithOutput(cmd string, args ...string) ([]byte, []byte, error) {
	var stdout, stderr bytes.Buffer
	c := exec.Command(cmd, args...)
	fmt.Println(c.String())
	c.Stdout = &stdout
	c.Stderr = &stderr
	err := c.Run()
	if err != nil {
		return nil, nil, &cmdError{
			cmd:    c.String(),
			stdout: stdout.Bytes(),
			stderr: stderr.Bytes(),
			err:    err,
		}
	}
	return stdout.Bytes(), stderr.Bytes(), nil
}

func runCmd(cmd string, args ...string) error {
	_, _, err := runCmdWithOutput(cmd, args...)
	return err
}

func runCmdSaveStdoutToFile(filename string, cmd string, args ...string) error {
	stdout, _, err := runCmdWithOutput(cmd, args...)
	f, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0600)

	if err != nil {
		return err
	}

	n, err := f.Write(stdout)
	if n != len(stdout) || err != nil {
		return fmt.Errorf("could not write entire output to %s, %v", filename, err)
	}
	f.Close()

	os.Chown(filename, uid, gid)

	return nil
}

func runUnprivCmdWithOutput(cmd string, args ...string) ([]byte, []byte, error) {
	var attrs syscall.SysProcAttr
	var stdout, stderr bytes.Buffer
	attrs.Credential = &creds
	c := exec.Command(cmd, args...)
	c.SysProcAttr = &attrs
	fmt.Println("Unpriv", c.String())
	c.Stdout = &stdout
	c.Stderr = &stderr
	err := c.Run()
	if err != nil {
		return nil, nil, &cmdError{
			cmd:    c.String(),
			stdout: stdout.Bytes(),
			stderr: stderr.Bytes(),
			err:    err,
		}
	}

	return stdout.Bytes(), stderr.Bytes(), nil
}

func runUnprivCmd(cmd string, args ...string) error {
	_, _, err := runUnprivCmdWithOutput(cmd, args...)
	return err
}

func naturalNumber(s string) int {
	n, err := strconv.Atoi(s)

	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	if n < 0 {
		fmt.Println("negative value")
		os.Exit(1)
	}

	return n
}

func runTests(id, as string) error {
	containerName := fmt.Sprintf("bgptest_%s", id)
	err := runCmd("bash", "disconnect.sh", as)
	if err != nil {
		return err
	}
	err = runCmd("bash", "configure_container.sh", id, as)
	if err != nil {
		return err
	}
	err = runCmd("bash", "runall.sh", as, "clear ip bgp *")
	if err != nil {
		return err
	}
	err = runCmd("bash", "start_exabgp.sh", id, as)
	if err != nil {
		return err
	}
	err = runUnprivCmd("python3", "gentest.py", id, as)
	if err != nil {
		return err
	}
	err = runCmd("bash", "copy.sh", id, as)
	if err != nil {
		return err
	}
	err = runCmd("docker", "exec", containerName, "python3", "test_as.py")
	if err != nil {
		return err
	}
	filename := fmt.Sprintf("lg_%s_%s", id, as)
	err = runCmdSaveStdoutToFile(filename, "bash", "runall.sh", "-0", as, "sh ip bgp")
	if err != nil {
		return err
	}
	filename = fmt.Sprintf("json_%s_%s", id, as)
	err = runCmdSaveStdoutToFile(filename, "bash", "runall.sh", "-0", as, "sh ip bgp json")
	if err != nil {
		return err
	}
	err = runCmd("bash", "copy_back.sh", id, as, username)
	if err != nil {
		return err
	}
	err = runUnprivCmd("python3", "bundle_results.py", id, as)
	if err != nil {
		return err
	}
	err = runCmd("bash", "connect.sh", as)
	if err != nil {
		return err
	}

	return nil
}

func launch(id int, c, done chan int) {
	time.Sleep(1 * time.Second)
	err := runCmd("bash", "launch_container.sh", strconv.Itoa(id))
	err_brk := false

	if err != nil {
		fmt.Println("Problem launching container ", id)
		fmt.Println(err)
		done <- -1
		return
	}
	for {
		as := <-c
		if as == -1 {
			break
		}
		err = runTests(strconv.Itoa(id), strconv.Itoa(as))
		if err != nil {
			fmt.Println("Container ", id)
			fmt.Println(err)
			err = runCmd("bash", "connect.sh", strconv.Itoa(as))
			if err != nil {
				fmt.Println("Could not connect network back:", err)
				fmt.Println("Quitting because too many errors")
				err_brk = true
				break
			}
		}
	}
	err = runCmd("bash", "cleanup_container.sh", strconv.Itoa(id))
	if err != nil {
		fmt.Println("Container ", id)
		fmt.Println(err)
		done <- -id
		return
	}
	if err_brk {
		done <- -id
		return
	}
	done <- id
}

func main() {
	start_time := time.Now()
	if len(os.Args) != 4 {
		fmt.Printf("Usage: %s username count as_list\n", os.Args[0])
		os.Exit(1)
	}

	username = os.Args[1]
	setupUser(username)

	ncontainer := naturalNumber(os.Args[2])

	slist := strings.Split(os.Args[3], ",")
	list := make([]int, len(slist))
	for i, v := range slist {
		list[i] = naturalNumber(v)
	}
	sort.Ints(list)
	for i := 1; i < len(list); i++ {
		if list[i-1] == list[i] {
			fmt.Println("No duplicates allowed in list")
			os.Exit(1)
		}
	}

	fmt.Println(ncontainer, list)
	if ncontainer > len(list) {
		fmt.Println("More container than ASes make no sense, reducing to number of ASes")
		ncontainer = len(list)
	}

	/* chans to distribute the AS list, done for threads to signal they are done */
	chans := make(chan int)
	done := make(chan int)
	for i := 1; i <= ncontainer; i += 1 {
		go launch(i, chans, done)
	}

	ndone := 0
	nsent := 0
	wlist := make([]int, len(list))
	copy(wlist, list)

	for ndone != ncontainer {
		var v int

		if len(wlist) > 0 {
			v = wlist[0]
		} else {
			v = -1
		}

		select {
		case chans <- v:
			nsent += 1
			if len(wlist) > 0 {
				wlist = wlist[1:]
			}
			continue
		case id := <-done:
			ndone += 1
			if id < 0 {
				fmt.Println("Error from ", -id)
			} else {
				fmt.Println(id, " is done")
			}
		}
	}

	if len(wlist) > 0 {
		fmt.Println("Failed to test all ASes")
		fmt.Printf("%d of %d ASes not tested\n", len(wlist), len(list))
		os.Exit(1)
	}

	/* Each AS + -1 to stop */
	if nsent != ncontainer+len(list) {
		fmt.Printf("Sent %d values but only %d containers\n", nsent, ncontainer)
		os.Exit(1)
	}

	fmt.Println("Done after", time.Since(start_time).String())
}
