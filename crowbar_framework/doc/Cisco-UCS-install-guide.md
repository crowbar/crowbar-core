# Cisco UCS integration barclamp

## Prerequisites

In Cisco’s UCS Manager, it will be necessary to create 2 server
profiles at the root level.  They are `susecloud-compute` and
`susecloud-storage`.  These names are case sensitive.

### `susecloudcompute`

* To be used for preparing systems as compute nodes for SUSE Cloud
* Minimum Requirements
    * 20GB Storage
    * 8GB RAM
    * 1 NIC
    * Processor supporting AMD-V or Intel-VT

### `susecloudstorage`

There are 3 types of available storage: `swift`, `nova`, and `ceph`.

### UCS administrator account

A user account must be created with administrative rights in the Cisco
UCS Manager, and the barclamp will use the credentials of that
account.

The account must have access to the `susecloud` templates and be able
to create service profiles in the root and associate them with
physical hardware.

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
