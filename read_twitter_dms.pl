#!/usr/bin/perl

# READING DIRECT MESSAGES

use 5.010 ;
use strict ;
use Carp ;
use Data::Dumper ;
use DBI ;
use Getopt::Long ;
use IO::Interactive 'interactive' ;
use Net::Twitter ;
use WWW::Shorten 'TinyURL' ;
use YAML qw{ DumpFile LoadFile } ;

my $db ;
my $config = config() ;
connect_to_db() ;
my $prev_messages = get_previous_messages( $db ) ;

# GET key and secret from http://twitter.com/apps
my $twit = Net::Twitter->new(
    traits          => [ 'API::REST', 'OAuth' ],
    consumer_key    => $config->{ consumer_key },
    consumer_secret => $config->{ consumer_secret },
    ) ;

# You'll save the token and secret in cookie, config file or session database
my ( $access_token, $access_token_secret ) ;
( $access_token, $access_token_secret ) = restore_tokens( $config->{ user } ) ;

if ( $access_token && $access_token_secret ) {
    $twit->access_token( $access_token ) ;
    $twit->access_token_secret( $access_token_secret ) ;
    }

unless ( $twit->authorized ) {

    # You have no auth token
    # go to the auth website.
    # they'll ask you if you wanna do this, then give you a PIN
    # input it here and it'll register you.
    # then save your token vals.

    say "Authorize this app at ", $twit->get_authorization_url,
        ' and enter the PIN#' ;
    my $pin = <STDIN> ;    # wait for input
    chomp $pin ;
    my ( $access_token, $access_token_secret, $user_id, $screen_name ) =
        $twit->request_access_token( verifier => $pin ) ;
    save_tokens( $config->{ user }, $access_token, $access_token_secret ) ;
    }

my $direct_messages = $twit->direct_messages(  ) ;

for my $message ( @$direct_messages ) {
    my $id = $message->{ id_str } ;
    my $text = $message->{ text } ;
    my $sender = lc $message->{ sender }->{ screen_name } ;

    if ( grep {/$sender/} @{ $config->{ senders } } ) {
        if ( ! $prev_messages->{ $id } ) {
            handle_message( $db , $message )
            }
        }

    }

exit ;


#========= ========= ========= ========= ========= ========= =========

sub config {
    my $config_file = $ENV{ HOME } . '/.twitter_dm.cnf' ;
    my $config      = LoadFile( $config_file ) ;
    return $config ;
    }

sub connect_to_db {
    my $db_file     = $ENV{ HOME } . '/.mydb.cnf' ;
    my $db_hash     = LoadFile( $db_file ) ;
    my $source = "dbi:mysql:$db_hash->{database}:$db_hash->{host}:$db_hash->{port}" ;
    $db = DBI->connect( $source, $db_hash->{ user }, $db_hash->{ password } ) ;
    }

sub restore_tokens {
    my ( $user ) = @_ ;
    my ( $access_token, $access_token_secret ) ;
    if ( $config->{ tokens }{ $user } ) {
        $access_token = $config->{ tokens }{ $user }{ access_token } ;
        $access_token_secret =
            $config->{ tokens }{ $user }{ access_token_secret } ;
        }
    return $access_token, $access_token_secret ;
    }

sub save_tokens {
    my ( $user, $access_token, $access_token_secret ) = @_ ;
    my $config_file = $ENV{ HOME } . '/.twitter_dm.cnf' ;
    $config->{ tokens }{ $user }{ access_token }        = $access_token ;
    $config->{ tokens }{ $user }{ access_token_secret } = $access_token_secret ;
    DumpFile( $config_file, $config ) ;
    return 1 ;
    }

sub get_previous_messages {
    my ( $db ) = @_ ;
    my $sql = <<SQL ;
        SELECT id , twitter_id FROM ppm_dms ;
SQL
    my $sth = $db->prepare( $sql ) ;
    $sth->execute() or croak $db->errstr ;
    my $ptr = $sth->fetchall_hashref( 'twitter_id' ) ;
    return $ptr ;
    }

sub handle_message {
    my ( $db , $message ) = @_ ;
    my $id = $message->{ id_str } ;
    my $sender = $message->{ sender }->{ screen_name } ;
    my $body  = $message->{ text } ;
    my @data ;
    push @data , $id , $sender , $body ;
    my $sql = <<'SQL' ;
        INSERT INTO ppm_dms ( twitter_id , sender , message , is_sent )
        VALUES (? , ? , ? , 0 )
SQL
    my $sth = $db->prepare( $sql ) ;
    $sth->execute( @data ) or croak $db->errstr ;
    my $rows = $sth->rows() ;
    }
