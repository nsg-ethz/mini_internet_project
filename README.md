# An Open Platform to Teach How the Internet Practically Works

Welcome in the official repositery of the mini-Internet project.

### The mini-Internet project

A mini-Internet is a virtual network mimicking the real Internet. Among others, there are routers, switches and hosts that are located in different ASes. A mini-Internet runs in a single server and is tailored to teach how the Internet practically works. Each components of the network is running in its own dedicated linux container, that are remotely accessible by the students with simple ssh connections.

The mini-Internet project is the flagship piece of our [Communication Networks course](https://comm-net.ethz.ch/) at ETH Zurich since 2016. The concept is rather simple: we let each student group operate their own AS. Their goal? Enabling Internet-wide connectivity.

We find this class-wide project to be invaluable in teaching our students how the Internet infrastructure practically works. Among others, our students have a much deeper understanding of Internet operations alongside their pitfalls. Besides students tend to love the project: clearly the fact that all of them need to cooperate for the entire Internet to work is empowering

In [2020_assignment_eth](2020_assignment_eth), we further describe how we used the mini-Internet at ETH in the 2020 iteration of our Communication Networks lecture.
While the mini-Internet project works well for our introductory class, observe that it can be adapted for various teaching objectives.

### Build _your_ mini-Internet

With this platform, you can easily build your own mini-Internet, tailored for your teaching objectives.
The documentation as well as the source code of the platform can be found in the [platform](platform) directory.
In a nutshell, after defining your topology in configuration files, you can build your mini-Internet with a bash script and use it for your networking class. 

If you use the platforn, please cite our **[technical report]( https://arxiv.org/pdf/1912.02031.pdf)**. Here is the bibtex:
```
@article{Holterbach2019AnOP,
  title={An Open Platform to Teach How the Internet Practically Works},
  author={Thomas Holterbach and Tobias B{\"u}hler and Tino Rellstab and Laurent Vanbever},
  journal={ArXiv},
  year={2019},
  volume={abs/1912.02031}
}
```

### News

*15/04/20:* Fixed a security issue with the docker containers. Now students' containers only run with limited capabilities. \
*18/03/20:* Several fixes (e.g., prevent containers to crash because too many processes are running) and improvements (e.g., configure different internal topologies)

### Useful links

- We presented the mini-Internet at NANOG 78 in February 2020. The [talk](https://www.youtube.com/watch?v=8SRjTqH5Z8M&list=PLO8DR5ZGla8jSzWlrWt_cz13LLAz44rHY&index=11&t=0s) is available on youtube.

- We wrote a [blogpost](https://blog.apnic.net/2020/04/14/develop-your-own-mini-internet-to-teach-students-virtually-about-network-operations/) on the APNIC website about the mini-Internet.

### Contacts

Thomas Holterbach <thomahol@ethz.ch> \
Tobias Bühler <buehlert@ethz.ch> \
Tino Rellstab <tino.rellstab@gmail.com> \
Laurent Vanbever <lvanbever@ethz.ch> \
[NSG Group website](https://nsg.ee.ethz.ch/home/)

### Disclaimer

This platform has been tailored to teach how the Internet works in our Communication Networks lecture at ETH Zurich. Although this platform may be useful for other kind of purposes (research, experiments, etc), it has not been designed for them.

If you want to use this platform for your networking class, we recommend that you spent some time understanding the code and how we build the mini-Internet, and we recommend you to try it first before using it with actual students.
We assume no responsibility or liability for any problem you may encounter while using the platform.
