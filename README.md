# Nextpanel Installation Guide

Nextpanel is a web hosting control panel designed for ease of use and robust functionality. Below are the steps to install Nextpanel on a Linux server.

## Prerequisites

- A Linux-based Ubuntu server 20, 22, or 24
- Sudo or root privileges

## Installation Steps

1. **Download and install the Nextpanel script:**

   If you are not logged in as root user enter this command to switch to root user:

   ```bash
   sudo -s

2. **Download and install the Nextpanel script:**

   Run the following command to download the installation script and make it executable:

   ```bash
   wget https://raw.githubusercontent.com/topwebdesignco/nextpanel-install/refs/heads/main/nextpanel.sh -O nextpanel.sh && chmod +x nextpanel.sh && clear && ./nextpanel.sh
