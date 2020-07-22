#!/bin/bash

if [ -z "$1" ]; then
	echo "Usage: configure-microk8s.sh {nodes}"
	exit 1
fi

NODES="$1"

echo "Configuring microk8s on each node..."
echo "» Sit back and relax, this is going to take a while"

echo "-- master"
multipass exec kube-master -- sudo usermod -a -G microk8s ubuntu
multipass exec kube-master -- /snap/bin/microk8s.kubectl cluster-info
multipass exec kube-master -- /snap/bin/microk8s.enable dns ingress rbac metrics-server storage

for ((i=1;i<=$NODES;i++));
do
  echo "-- worker $i"
  multipass exec kube-node-$i -- sudo usermod -a -G microk8s ubuntu
  multipass exec kube-node-$i -- /snap/bin/microk8s.kubectl cluster-info
  multipass exec kube-node-$i -- /snap/bin/microk8s.enable dns ingress rbac metrics-server storage
  multipass exec kube-node-$i -- /snap/bin/microk8s.status
done

echo "Next steps..."
echo "-- execute [ multipass exec kube-master -- /snap/bin/microk8s.add-node ] once for each of the $NODES kube-node(s) to be added to kube-master"
echo "-- optionally execute [ multipass exec kube-master -- /snap/bin/microk8s.config ] appending or replacing output to ~/.kube/config"
