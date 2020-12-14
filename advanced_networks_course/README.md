# Advanced Topics in Computer Networks course

We designed two exercises based on the mini-Internet to teach our students about advanced concepts and protocols such as MPLS, LDP, BGP Free Core, BGP VPN, VRF and Multicast.
Note unlike for the mini-Internet project, here each student has its own mini-Internet running its VM. 

To run those exercises, you need to clone the mini-Internet github repository in the $HOME directory, then you can run the script `build/build.sh` to build the topology (available in the directory of the exercise).

More detail on how to run the exercises can be found in their README.

### BGP VPN MPLS

In the directory [BGP_VPN_MPLS](BGP_VPN_MPLS) we show the exercise we give to our students and where the goal is to implement a BGP VPN with MPLS and some additional policies. 

### Multicast

In the directory [Multicast](Multicast) we show the exercise we give to our students and where the goal is to configure Multicast using the PIM and IGMP protocol. They can then test Multicast on a VLC video streaming.
