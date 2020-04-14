# An Open Platform to Teach How the Internet Practically Works

This is the official repositery of the mini-Internet project.

### The mini-Internet project

A mini-Internet is a virtual network mimicking the real Internet. Among others, there are routers, switches and hosts that are divided in different ASes. A mini-Internet runs in a single server and is tailored to teach how the Internet practically works. Each components of the network is running in its own dedicated linux container, that are remotely accessible by the students with simple ssh connections. 

We use the mini-Internet at ETH Zurich in our Communication Networks course since 2016. More precisely, we let each student group operate their own AS. Their goal? Enabling Internet-wide connectivity. \
Our students learn how to configure the different routing protocols. Besides, the learn that Internet is the result of a collective effort: they often have to collaborate and debug together. 

The mini-Internet project works well for our introductory class, yet it can be adapted for various teaching objectives.

### Build _your_ mini-Internet

The documentation as well as the source code of the mini-Internet can be found in the [platform](platform) directory. \
In [2020_assignment_eth](2020_assignment_eth) we describe how we used the mini-Internet at ETH in the 2020 iteration of our [Communication Networks](https://comm-net.ethz.ch/) lecture.

Please cite our **[technical report]( https://arxiv.org/pdf/1912.02031.pdf)** if you use the platform. Here is the bibtex:
```
@article{Holterbach2019AnOP,
  title={An Open Platform to Teach How the Internet Practically Works},
  author={Thomas Holterbach and Tobias B{\"u}hler and Tino Rellstab and Laurent Vanbever},
  journal={ArXiv},
  year={2019},
  volume={abs/1912.02031}
}
```


For further information, you can watch our [talk](https://www.youtube.com/watch?v=8SRjTqH5Z8M&list=PLO8DR5ZGla8jSzWlrWt_cz13LLAz44rHY&index=11&t=0s) we gave at NANOG 78 (February 2020).

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

