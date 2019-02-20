DESCRIPTION
===========

This cookbook contains providers and templates for integrating
with SUSE Enterprise Storage (Ceph).

Resources/Providers
===================
config
----------
Manages ceph configuration and keyring files based on information
stored in crowbar-config/ses data bag.

- `:create` creates the configuration and keyring files. The name 
  of resource should point to the target service which will use
  ceph configuration.

### Examples
``` ruby
ses_config "cinder" do
  action :create
end
```

LICENSE AND AUTHORS
--------

* Author: Walter Boring <wboring@suse.com>
* Author: Jacek Tomasiak <jtomasiak@suse.com>

* Copyright 2018-2019 SUSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
