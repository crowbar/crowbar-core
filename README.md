Welcome to a Barclamp for the Crowbar Framework project
=======================================================

The code and documentation is distributed under the [Apache 2 license](http://www.apache.org/licenses/LICENSE-2.0.html).
Contributions back to the source are encouraged.

The [Crowbar Framework](https://github.com/crowbar/crowbar) is currently maintained by [SUSE](http://www.suse.com/) as
an [OpenStack](http://openstack.org) installation framework but is prepared to be a much broader function tool. It was
originally developed by the [Dell CloudEdge Solutions Team](http://dell.com/openstack).

A Barclamp is a module component that implements functionality for Crowbar. Core barclamps operate the essential
functions of the Crowbar deployment mechanics while other barclamps extend the system for specific applications.

**This functonality of this barclamp DOES NOT stand alone, the Crowbar Framework is required**

About this barclamp
-------------------

[![Build Status](https://travis-ci.org/crowbar/barclamp-suse-manager-client.svg?branch=master)](https://travis-ci.org/crowbar/barclamp-suse-manager-client)
[![Code Climate](https://codeclimate.com/github/crowbar/barclamp-suse-manager-client/badges/gpa.svg)](https://codeclimate.com/github/crowbar/barclamp-suse-manager-client)
[![Test Coverage](https://codeclimate.com/github/crowbar/barclamp-suse-manager-client/badges/coverage.svg)](https://codeclimate.com/github/crowbar/barclamp-suse-manager-client)
[![Dependency Status](https://gemnasium.com/crowbar/barclamp-suse-manager-client.svg)](https://gemnasium.com/crowbar/barclamp-suse-manager-client)
[![Join the chat at https://gitter.im/crowbar](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/crowbar)

Information for this barclamp is maintained on the [Crowbar Framework Wiki](https://github.com/crowbar/crowbar/wiki)

Steps to setup
--------------

* Install SUSE Manager Server
* Inside SUSE Manager, create an activation key. The activation key will be used in the barclamp's WebUI.
* Download the `https://your-manager-server.example.com/pub/rhn-org-trusted-ssl-cert-*-*.noarch.rpm` file (check the
  version number) as `chef/cookbooks/suse-manager-client/files/default/ssl-cert.rpm` (in this barclamp's directory tree).
* Reinstalling the barclamp might be required in order for crowbar to take notice of the new file. Do this with:
  `/opt/dell/bin/barclamp_install.rb --rpm suse-manager-client`
* Now apply the barclamp from Crowbar's WebUI on selected nodes.

Contact
-------

To get in contact with the developers you have multiple options, all of them are listed below:

* [Google Mailinglist](https://groups.google.com/forum/#!forum/crowbar)
* [Gitter Chat](https://gitter.im/crowbar)
* [Freenode Webchat](http://webchat.freenode.net/?channels=%23crowbar)

Legals
------

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
