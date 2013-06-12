Welcome to a Barclamp for the Crowbar Framework project
=======================================================
_Copyright 2013, SUSE_

The code and documentation is distributed under the Apache 2 license (http://www.apache.org/licenses/LICENSE-2.0.html). Contributions back to the source are encouraged.

The Crowbar Framework (https://github.com/crowbar/crowbar) was developed by the Dell CloudEdge Solutions Team (http://dell.com/openstack) as a OpenStack installer (http://OpenStack.org) but has evolved as a much broader function tool. 
A Barclamp is a module component that implements functionality for Crowbar.  Core barclamps operate the essential functions of the Crowbar deployment mechanics while other barclamps extend the system for specific applications.

* The functionality of this barclamp DOES NOT stand alone, the Crowbar Framework is required. *


About this Barclamp: SUSE Manager Client
-------------------------------

This barclamp can be used to register nodes to SUSE Manager.

Steps to setup:

Install SUSE Manager Server.

Inside SUSE Manager, create an activation key. The activation key will be used in the barclamp's WebUI.

Download the `https://your-manager-server.example.com/pub/https://cloud-sm/pub/rhn-org-trusted-ssl-cert-*-*.noarch.rpm` file (check the version number) as `chef/cookbooks/suse-manager-client/files/default/ssl-cert.rpm` (in this barclamp's directory tree).

Now apply the barclamp from Crowbar's WebUI on selected nodes.


Legals
-------------------------------------
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
