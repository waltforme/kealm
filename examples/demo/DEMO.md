# Demo

The demo is running on 2 VMs on AWS. It is recommended to use iTerm2 and tmux 

# Requirements

- [iTerm2](https://iterm2.com) - if running on macOS
- Public ssh key should be placed in `~/.ssh/authorized_keys` on 3.131.159.89. Ask me for help on setting this up.

## Setup

1. Open an iTerm2 and start a tmux session to ubuntu@3.131.159.89 as described [here](https://medium.com/@gveloper/using-iterm2s-built-in-integration-with-tmux-d5d0ef55ec30). Make the window large as the screen.
2. COMMAND+T to open a second tab (if asked which type of tab, select tmux tab)
3. COMMAND+T to open a third tmux tab
4. On third tab, type:
   ```shell
   ssh 18.116.240.175
   ```
   After ssh session starts, type:
   ```shell
   cdd
   ./startEdge2.sh clean
   ``` 
   wait until kcp started.
5. On second tab, type:
   ```shell
   kind delete cluster --name cluster1
   kind delete cluster --name cluster2
   cdd
   ./startKcpForDemo.sh clean
   ```
   Wait until all started (usually when you see the line `/home/ubuntu/podman-controller.log <==` )
6. On first tab:
   - COMMAND+D
   - COMMAND+SHIFT+D
   The window should now be split in 3. One on the left, two on the right side.
7. On the left window type:
   ```shell
   cdd
   ./script
   ```
8. On the top right window type:
   ```shell
   cdd
   ./script-cluster
   ```
9. On the bottom right window type:
   ```shell
   cdd
   ./script-edge
   ```

Demo is ready to go !

## Demo

Start on window on the left. 
- Press enter to show command
- Enter again to execute the command.
- Make sure that command is completely printed on screen before hitting enter to execute command or an extra line gets inserted
- After command: `vim ../examples/deployment1.yaml` is executed, click to top right window and run that portion of demo.
- After the `cluster2> kubectl get deployments` command is run, click again on left window and press `ESC` and `q` to exit vim 
- Run commands up to `hub> kubectl get deployments` 
- Switch to top right window, run commands up to `cluster1> kubectl get pods`
- Click on left window and run up to `vim ../examples/deployment2.yaml` to show the yaml for group2 deployment
- Click on bottom right window, run commands up to `edge2> kubectl get deployments` to show edge2 is disconnected
- Click on left window, press `ESC` and `q` to exit vim 
- Run commands up tp `hub> kubectl get deployments`
- Click on bottom right window, run commands up to `edge2> watch kubectl get deployments`
- It may take up to 30 s, but at some point you should see the deployment show up on edge2
  ```
  NAME                 AGE
  deployment2--edge2   40s
  ```
- Do CTRL+C to exit `watch`
- Run commands up to `ssh 18.116.240.175 podman pod list`  
- [Optional] - go back to hub and show last command ` hub> kubectl get deployments -o=custom-columns-file=template.txt` to see pods deployed by virtual and root deployment.

To restart the demo, do CTRL+C on each window on first tab and then restart again the script for each 
(`./script`, `'script-cluster`, `script-edge`). Note that each script will delete the resources created during 
previous runs (clusters, deployments and podman pods).

## Issues

Sometimes, after a couple of runs, the deployment targeted for cluster1 and cluster2 show up both on one cluster and
nothing shows on the other. 

*Workaround*: delete both kind clusters:

```shell
kind delete cluster --name cluster1
kind delete cluster --name cluster2
```

and restart KCP:

```shell
cdd
./startKcpForDemo.sh clean
```




