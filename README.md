# osbaseline

#### Table of Contents

<!-- vim-markdown-toc GFM -->

* [Description](#description)
* [Setup](#setup)
  * [What osbaseline affects](#what-osbaseline-affects)
  * [Setup Requirements](#setup-requirements)
  * [Beginning with osbaseline](#beginning-with-osbaseline)
* [Usage - For Repository Users](#usage---for-repository-users)
  * [Repositories only](#repositories-only)
  * [Manage OS Baseline](#manage-os-baseline)
    * [Included Scripts to Manage Groups](#included-scripts-to-manage-groups)
      * [Script invocation](#script-invocation)
* [Usage - For Repository Servers](#usage---for-repository-servers)
* [Limitations](#limitations)
* [Development](#development)

<!-- vim-markdown-toc -->

## Description

This module provides the ability to easily manage Operating System baseline levels.  It does 
this by setting up the package repositories (YUM for RedHat/AIX and Zypper for Suse).  It can 
be used to manage any repositories, but it's designed to work smoothly with https://github.com/Q-Technologies/lobm (the 
Linux OS Baseline Maker) - which basically uses symbolic links to snapshot repositories by date, ensuring all systems
have exacting the same patches (package versions) installed.

## Setup

### What osbaseline affects

It manages the package repositories a client is pointing to.

### Setup Requirements

It requires hiera data to drive the configuration and a set of groups in the classifier (setting an appropriate variable).

### Beginning with osbaseline

Simply include or call the class:
```
include osbaseline
```

or
```
class { 'osbaseline': }`
```

But, bear in mind, it doesn't support all OS's, so it's worth wrapping like this:
```
  # For Red Hat based systems - set up the OS baseline capabilities (e.g. repos)
  if $facts['os']['family'] == 'RedHat' {
    class { 'osbaseline': 
      purge_repos      => true,
    }
  }
```
The `purge_repos` option will force all unmanaged repositories to be removed.

## Usage - For Repository Users

### Repositories only

If you just want to use it to manage generic repositories, set **enforce_baseline** to false in heira or when calling the class:
```
class { 'osbaseline':
  enforce_baseline = false
}`
```

### Manage OS Baseline
If you want to manage the repositories as well as enforce an OS Baseline, you will need to set up some Node Classifer groups (or otherwise set
a global variable with the baseline version).  If this variable is not set it will fail a Puppet run saying the baseline variable is not set.

If using the Node Classifer, create a group that matches all the nodes you want to manage and set up a variable with the date of the 
baseline, e.g.: `osbaseline_date` = `2017-09-30`.  This can also be achieved by setting a fact, but is harder to manage.  

Create additional groups with different dates and move hosts between them as desired.  The repository URIs will be updated accordingly
on the next Puppet runs.

If `osbaseline::repos::do_update` is set to `true` in Hiera, the `yum distro-sync` operation will be run against the baseline repo only.
Currently a reboot is not performed, but this is expected to be added in the future.

#### Included Scripts to Manage Groups
There are included scripts to manage the creation of the groups and to make it easier to move nodes between the groups.  To install the scripts
on a host, set Hiera data along these lines in the scope you want them installed:
```
osbaseline::scripts::install: true
# The following two lines are defaults also
osbaseline::scripts::selection_script_path: /usr/local/bin/baseline_selection.pl
osbaseline::scripts::selection_config_path: /usr/local/etc/baseline_selection.yaml
osbaseline::scripts::selection_config:
  puppet_classify_host: puppet
  puppet_classify_port: 4433
  puppet_classify_cert: api_access
  puppet_ssl_path: /etc/puppetlabs/puppet/ssl
  puppetdb_host: localhost
  puppetdb_port: 8080
  group_names_prefix: OS Baseline
  default_osbaseline_date: '2017-08-31'
  default_group_rule: [ 'and', [ '~', ['facts','os', 'release', 'major'], '^[67]$'], [ '=', ['facts','os', 'family'], 'RedHat'] ]
```
It reality, this needs to be run on the Puppet master due to access to certificates.  If you want to run on another host, you can copy the 
access cert and the CA to another host.  Use `puppet cert generate api_access` to create a cert and add it to `/etc/puppetlabs/console-services/rbac-certificate-whitelist`.

##### Script invocation
```
baseline_selection.pl -a action -g group [-f] [node1] [node2] [node3]
```

* -a, the script actions:
  * init_soe - create the default group
  * empty_group - empty a group of the nodes pinned to it
  * add_to_group - pin a node to a group
  * list_group - list the nodes pinned to a group
  * list_groups - list all the sub groups in parent baseline group
  * add_group - add a new baseline group
  * purge_old_nodes - remove all the nodes not found in the PuppetDB
  * remove_from_group - remove the specified nodes from a group
  * remove_group - remove the specified group
* -g, specify a group name
* -f, force, e.g force the removal of a group even if nodes are pinned to it
* the list of nodes are required when adding/removing from a group

## Usage - For Repository Servers
Include the `osbaseline::server` class in the profile of your repository server:
```
  class { 'osbaseline::server': }
```

Create Hiera data along these lines for the server of the repositories:
```
osbaseline::server::configuration:
  baseline_dir: "/repository/baselines/"
  http_served_from: "/repository"
  http_server_uri: "http://yumrepo.example.com/repo"
  createrepo_cmd: "/usr/bin/createrepo"
  workers: 2

osbaseline::server::definitions:
  "CentOS_7_2017-08-31":
    description: Centos 7 as at the end of August 2017
    target: centos
    versions: 1 
    rpm_dirs:
      -
        dir: /repository/os/CentOS/7/base/x86_64/Packages/
        date: "2017-08-31"
      -
        dir: /repository/os/CentOS/7/updates/x86_64/Packages/
        date: "2017-08-31"
  "OracleLinux_7_2017-08-31":
    description: OracleLinux 7 as at the end of August 2017
    target: rhel
    versions: 1 
    rpm_dirs:
      -
        dir: /repository/os/OracleLinux/7/base/x86_64/Packages/
        date: "2017-08-31"
      -
        dir: /repository/os/OracleLinux/7/updates/x86_64/Packages/
        date: "2017-08-31"
```
We assume the relevant directories are exported via the Web.  NGINX config might look like this:
```
nginx::nginx_servers:
  'yum_repo':
    listen_port: 80
    server_name: ["yumrepo.example.com"]
    access_log: '/var/log/nginx/yum_repo.access.log'
    error_log: '/var/log/nginx/yum_repo.error.log'
    use_default_location: false
    locations:
      'repo_80':
        location: '/repo/'
        autoindex: 'on'
        www_root: '/repository/'
```
A cron entry could be created along these lines (depending on the module you are using):
```
cron_entries:
  'create_centos_baseline':
    command: '/usr/bin/lobm -c /etc/lobm/baselines/CentOS_7_2017-08-31.yaml -o $(date -d yesterday +''\%Y-\%m-\%d'')'
    user: 'yumrepo'
    hour: '0'
    minute: '0'
    monthday: '1'
```


## Limitations

Only tested on AIX, EL and Suse systems.  It is not designed for Debian based systems.

## Development

If you would like to contribute to or comment on this module, please do so at it's Github repository.  Thanks.

