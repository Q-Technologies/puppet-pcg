# == Class: pcg
class pcg (
  String $path,
  Boolean $install_pkg,
  Boolean $install_systemd_service,
  String $perl_path,
  Integer $port,
  String $owner,
  String $group,
  String $proxy_user,
  String $proxy_pass,
  String $proxy_proto,
  String $proxy_host,
  String $proxy_port,
  Data $config,
  Collection $roles,
  Collection $stacks,
  String $template,
){
  # Make sure the package is at the latest version
  if $install_pkg {
    package { 'pcg':
      ensure => latest,
    }
  }

  # Overwrite the template file if we have a new one
  if ! empty( $template ) {
    file{"${path}/templates/create_ec2_instance.pp.tt":
      owner   => $owner,
      group   => $group,
      mode     => '0644',
      content  => $template,
    }
  }
 
  # Write the role files
  $roles.each | $rolename, $role | {
    file{"${path}/roles/${rolename}.yml":
      owner   => $owner,
      group   => $group,
      mode     => '0644',
      content  => inline_template('<%= @role.to_yaml %>'),
    }
  }
  # Purge old role files
  file { "${path}/roles":
    ensure  => directory,
    purge   => true,
    recurse => true,
  }

  # Write the stack files
  $stacks.each | $stackname, $stack | {
    file{"${path}/stacks/${stackname}.yml":
      owner   => $owner,
      group   => $group,
      mode     => '0644',
      content  => inline_template('<%= @stack.to_yaml %>'),
    }
  }
  # Purge old stack files
  file { "${path}/stacks":
    ensure  => directory,
    purge   => true,
    recurse => true,
  }

  # Write the local configuration file
  if ! empty( $config ) {
    file{"${path}/config_local.yml":
      owner   => $owner,
      group   => $group,
      mode    => '0644',
      notify  => Service['pcg'],
      content => inline_template('<%= @config.to_yaml %>'),
    }
  }
  if $facts['service_provider'] == 'systemd' and $install_systemd_service {
    ::systemd::unit_file { 'pcg.service':
      content => epp('pcg/pcg.service.epp', {
        proxy_user  => $proxy_user,
        proxy_pass  => $proxy_pass,
        proxy_proto => $proxy_proto,
        proxy_host  => $proxy_host,
        proxy_port  => $proxy_port,
        path        => $path,
        port        => $port,
        user        => $owner,
        group       => $group,
        perl_path   => $perl_path,
      }),
    }
    file { '/etc/init.d/pcg':
      ensure  => absent,
    }
  }

  #Make sure the PCG service is running
  service { 'pcg':
    ensure => running,
    enable => true,
  }

}
