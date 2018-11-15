# == Class: pcg::client
class pcg::client (
  Boolean $install = false,
  String $location = '/usr/local/bin',
){
  # Install the client script if requested
  if $install {
    file{"${location}/manage_instance.pl":
      mode     => '0755',
      source   => 'puppet:///modules/pcg/manage_instance.pl',
    }
  }
 
}
