# Automatey

Automatey aims to get you quickly set up with a RHEL 7 server running a bunch of useful automation tools as docker containers. It assumes you've got a reasonable RHEL 7 build that's registered with subscription-manager. The build I'm working on has also been hardened to CIS 2.2 standards.

## What does what

1-packages.sh - Enables required repos, installs RPMS (so you get ansible) and enables and starts Docker engine.
2-awxbuild.sh - Builds AWX containers from github source and runs them.

## Setup

After cloning the repo...

```
cd automatey
./1-packages.sh 

```
