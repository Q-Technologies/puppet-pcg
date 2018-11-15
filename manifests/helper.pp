# == Class: pcg::helper
class pcg::helper (
  Boolean $install = false,
  String $location = '/var/www/html',
  String $owner = 'root',
  String $group = 'root',
  String $mode = '0644',
  String $repo_server = hiera("osbaseline::repo_server",''), 
  Data $pcg_config = hiera("pcg::config",{}),
  Collection $valid_sites = [],
  Collection $valid_network_names = [],
  Collection $valid_network_zones = [],
){

  include stdlib


  # Install the client script if requested
  if $install {
    file{"${location}/agent_install.sh":
      mode    => $mode,
      owner   => $owner,
      group   => $group,
      content => epp('pcg/agent_install.sh', { repo_server => $repo_server, 
                                               app_sub_envs => $pcg_config['app_sub_envs'],
                                               valid_sites => join( $valid_sites,  '|' ),
                                               valid_network_names => join( $valid_network_names,  '|' ),
                                               valid_network_zones => join( $valid_network_zones,  '|' ),
                                             }),
    }
  }
 
}
