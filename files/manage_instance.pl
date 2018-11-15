#!/usr/bin/env perl
#
# See help sub at the bottom for script description

use strict;
use 5.10.0;
use YAML qw( LoadFile Dump );
use Getopt::Std;
use Data::Dumper;
use JSON;
use LWP::UserAgent ();
use Config::INI::Reader;

getopts('ha:l:e:b:s:r:c:o:g:n:z:d:');

our( $opt_a, $opt_d, $opt_h, $opt_l, $opt_e, $opt_b, $opt_s, $opt_r, $opt_c, $opt_o, $opt_n, $opt_z, $opt_g );

# Show the help message and exit, if requested
if( $opt_h ){
    usage();
    exit;
} 

# Read in configuration data
my $conf_file = $ENV{HOME}."/.pcg_config.yaml";
if( ! -r $conf_file ){
    invoke_error( "You need to correctly configure $conf_file" );
}
my $config = LoadFile( $conf_file );

my $server_url = $config->{server_url};
my $userid = $config->{userid};
my $passwd = $config->{passwd};
my $ssl_ca_path = $config->{ssl_ca_path};

if( $ENV{AWS_ACCESS_KEY_ID} ){
    $config->{access_key_id}     = $ENV{AWS_ACCESS_KEY_ID};
    $config->{secret_access_key} = $ENV{AWS_SECRET_ACCESS_KEY};
} else {
    $opt_d = 'default' if ! $opt_d;
    my $aws_creds_file = $ENV{HOME}."/.aws/credentials";
    my $aws_creds;
    if( -r $aws_creds_file ){
        $aws_creds = Config::INI::Reader->read_file($aws_creds_file);
    }
    $config->{access_key_id}     = $aws_creds->{$opt_d}{aws_access_key_id};
    $config->{secret_access_key} = $aws_creds->{$opt_d}{aws_secret_access_key};
}

# Main program logic
if( $opt_l ){
    my $query = {};
    if( $opt_l =~ /^(os|zone|subnet|role|region|app_sub_env|size)(s)*(es)*$/ ){
        $query->{option} = $opt_l;
        $query->{cloud}  = $opt_c;
        $query->{region} = $opt_g;
        $query->{zone}   = $opt_z;
        list_options( $query, $1 );
     } elsif( $opt_l =~ /^all$/ ){
        for my $item ( qw( clouds sizes regions zones roles app_sub_env oses subnets) ){
            $query->{option} = $item;
            $query->{cloud}  = $opt_c;
            $query->{region} = $opt_g;
            $query->{zone}   = $opt_z;
            list_options( $query, $item );
        }
    } else {
        invoke_error( "Unknown option: $opt_l");
    }
} elsif( $opt_a ){
    my $type = 'instance';
    $type = 'stack' if $opt_a =~ /stack/;

    if( $opt_a =~ /^(show_*all|destroy|show|stop|start|list_stacks|show_stack|destroy_stack|create(_stack)*)$/ ){
        my $arr = [];
        if( @ARGV ){
            for my $instance ( @ARGV ){
                check_name( $instance ) if $opt_a eq 'create';
                my $data = {};
                $data->{cloud}             = $opt_c;
                $data->{access_key_id}     = $config->{access_key_id};
                $data->{secret_access_key} = $config->{secret_access_key};
                $data->{region}            = $opt_g;
                $data->{name}              = $instance;
                $data->{subnet}            = $opt_n if $opt_a =~ /create/;
                $data->{size}              = $opt_s if $opt_a =~ /^create$/;
                $data->{role}              = $opt_r if $opt_a =~ /^create$/;
                $data->{app_sub_env}       = $opt_e if $opt_a =~ /create/;
                $data->{os}                = $opt_o if $opt_a =~ /^create$/;
                $data->{availability_zone} = $opt_z if $opt_a =~ /create/;
                $data->{puppet_branch}     = $opt_b if $opt_a =~ /create/;
                push @$arr, $data;
            }
        } elsif( $opt_a =~ /^(show_*all|list_stacks)$/ ) {
            my $data = {};
            $data->{cloud}             = $opt_c;
            $data->{access_key_id}     = $config->{access_key_id};
            $data->{secret_access_key} = $config->{secret_access_key};
            $data->{region}            = $opt_g;
            push @$arr, $data;
        } else {
            invoke_error( "Please specify the $type(s) for $opt_a");
        }
        #say encode_json $arr;
        #say "This takes a while to run..." if $opt_a eq 'destroy';
        my $result = send_ajax_request( 'do', { userid => $userid, passwd => $passwd, Event => 'CLI', Action => $opt_a, PayLoad => $arr } );
        if( $result ){
            say Dump( $result );
        } else {
            say "No ${type}s exist.";
        }
    } else {
        invoke_error( "Unknown command: $opt_a");
    }
} else {
    invoke_error( "Specify either an action or something to list");
}

sub list_options {
    my $query = shift;
    my $name = shift;
    my $result;
    my $data =   { userid => $userid, passwd => $passwd, Query => $query };

    my $result = send_ajax_request( 'list', $data );
    #say Dumper( $data );
    say "The following can be selected from for $name:";
    if( $result and ref($result) eq 'ARRAY' ){
        for my $option ( sort @{$result} ){
            say "\t$option";
        }
    } else {
        say Dumper( $result );
        invoke_error( "Response from server was in an unexpected format");
    }
}

sub invoke_error {
    my $msg = shift;
    say $msg;
    exit 1;
}

sub check_name {
    my $hostname = shift;
    my $result = send_ajax_request( 'check/hostname/is/ok', { userid => $userid, passwd => $passwd, hostname => $hostname } );
    #say Dumper( $result );
    if( $result->{result} ne "success" ) {
        say $result->{msg};
        exit 1;
    }
}

sub send_ajax_request {
    my $type = shift;
    my $data = encode_json shift;
    my $result;

    my $req = HTTP::Request->new( 'POST', $server_url."/api/".$type );
    $req->header( 'Content-Type' => 'application/json' );
    $req->header('X-Requested-With' => "XMLHttpRequest");
    $req->content( $data );
    my %ssl_opts;
    if( $ssl_ca_path ){
        %ssl_opts = ( ssl_opts => {
                                    SSL_ca_path     => $ssl_ca_path,
                                    verify_hostname => 0,
                                  } );
    }
    my $ua = LWP::UserAgent->new( %ssl_opts );
    $ua->timeout(120);
    my $response = $ua->request( $req );

    if ($response->is_success) {
        $result = decode_json $response->decoded_content;
        if( $result->{result} ne "success" ){
            say Dumper( $result );
            die "Error: ".$result->{msg};
        }
    }
    else {
        #die join( "\n", Dumper( $result ), $response->status_line);
        die $response->status_line;
    }
    return $result->{data};
}

sub usage {
    say <<"END";
\nManage cloud images using Puppet\n
Usage:\n
$0 [options] [command] [objects]\n
Options:
\t-h this message
\t-a issue an  action:
\t\t show_all - show all cloud instances under the spcified credentials
\t\t show - show a specific cloud instance
\t\t destroy - stop and completely remove a specific cloud instance
\t\t start - ensure an existing instance is running
\t\t stop - ensure an existing instance is not running
\t\t create - create a new cloud instance.  No action if one by that name exists
\t\t create_stack - create a new cloud stacks.  Requires generic stack name.
\t\t list_stacks - provides a list of all stacks
\t\t show_stack - show details about a specifc cloud stack(s) and its instances
\t\t destroy_stack - destroy an existing stack and all its instances
\t-l list choices of:
\t\t cloud
\t\t region - cloud region
\t\t zones - availability zones
\t\t os - operating system
\t\t roles - server roles
\t\t size - instance sizes
\t\t app_sub_env - the application sub environment
\t-d specify the access codes (credentials) to use from ~/.aws/credentials
\t-e specify the application sub environment
\t-c specify the cloud to deploy into
\t-s specify the size of the instance
\t-r specify the server role to use
\t-g specify the cloud region to use
\t-z specify the cloud availability zone to use
\t-n specify the cloud subnet to use
\t-o specify the operating system to install
\t-b specify the Git branch of the Puppet code to use (override default for environment)

Configuration:
\tCreate a file in your home called: .pcg_config.yaml
\tWith the contents along the following lines:

\t\t---
\t\tserver_url: 'http://pcghost.example.com:3011'
\t\tuserid: user
\t\tpasswd: 'secret'
END
}
