# Cisco UCS integration barclamp

## Functionality

This barclamp communicates with a Cisco UCS Manager instance via its
XML-based API server, and can perform the following functions:

* Instantiate UCS service profiles for SUSE Cloud compute and
  storage nodes from predefined UCS service profile templates.
* Reboot and power up/down nodes

## Prerequisites

In Cisco’s UCS Manager, it is necessary to create two service profile
templates called `suse-cloud-compute` and `suse-cloud-storage`.  These
names are case sensitive.

### `suse-cloud-compute` service profile template

This service profile template is to be used for preparing systems as
SUSE Cloud compute nodes.  Minimum requirements:

* 20GB storage
* 8GB RAM
* 1 NIC
* Processor supporting AMD-V or Intel-VT

### `suse-cloud-storage` service profile template

This service profile template is to be used for preparing systems as
SUSE Cloud storage nodes.

### UCS administrator account

A user account must be created with administrative rights in the Cisco
UCS Manager, and the barclamp will use the credentials of that
account.

The account must have access to the above service profile templates,
and have authorization to create service profiles and associate them
with physical hardware.

## Configuration

* Log in to the Crowbar admin interface: http://yourhost:3000
* There should now be a tab labelled "UCS".
* Click the UCS tab.  The settings screen will be opened where the
  following information needs to be entered.
    * URL - this should have the form of: http://ucsmanagerhost/nuova
    * Username & Password - credentials from the administrator account
      described above.

## Usage

* Click the UCS tab in the Crowbar admin interface.
* Identify the servers to be used for compute or storage, select the servers,
  select the action and click the update button.  This action may take many
  minutes to fully complete.  
* To refresh the screen, click the UCS tab (or Dashboard sub-menu item).

## Troubleshooting

All troubleshooting should be done within the Cisco UCS Manager interface.
