#!/usr/bin/perl -w
use strict;
use LWP::Simple;
use JSON;
use Data::Dumper;
use URI::Escape;
use Date::Calc qw/Gmtime N_Delta_YMDHMS/;
use IRC::Utils ':ALL';

my $url = 'http://wiki.unvanquished.net/api.php?format=json&action=query&list=recentchanges&rcprop=title%7Csizes%7Cflags%7Cuser%7Ctimestamp%7Ccomment';
my $wikiurl = "http://wiki.unvanquished.net/index.php/";

use warnings;
use POE qw(Component::IRC);

my $nickname = 'Wikiflips';
my $ircname  = 'The Unv Wiki notifier bot';
my $server   = 'irc.freenode.org';
my @channels = ('#unvanquished-dev');
my $lasttime = 0;

# We create a new PoCo-IRC object
our $irc = POE::Component::IRC->spawn(
  nick => $nickname,
  ircname => $ircname,
  server  => $server,
) or die "Oh noooo! $!";

POE::Session->create(
  package_states => [
  main => [ qw(_start irc_001 pollWiki) ],
  ],
  heap => { irc => $irc },
);

$poe_kernel->run();

sub _start {
  my $heap = $_[HEAP];

  # retrieve our component's object from the heap where we stashed it
  my $irc = $heap->{irc};
  $irc->yield( register => 'all' );
  $irc->yield( connect => { } );
  return;
}

sub irc_001 {
  my $sender = $_[SENDER];

  # Since this is an irc_* event, we can get the component's object by
  # accessing the heap of the sender. Then we register and connect to the
  # specified server.
  my $irc = $sender->get_heap();

  print "Connected to ", $irc->server_name(), "\n";

  # we join our channels
  $irc->yield( join => $_ ) for @channels;
  $irc->yield( &pollWiki );
  return;
}


sub pollWiki
{
  my $wiki_data= decode_json(get($url));
  my @data = @{$wiki_data->{'query'}{'recentchanges'}};
  my $announcements = {};

  if (intifyDate($data[0]->{'timestamp'}) == $lasttime)
  {
    $_[KERNEL]->delay( pollWiki => 120 );
    return;
  }

  for (@data)
  {
    last if intifyDate($_->{'timestamp'}) <= $lasttime;
    my $change = 0;
    $change = $_->{'newlen'} - $_->{'oldlen'} if $_->{'newlen'};
    $announcements->{$_->{'user'}} = [] unless exists $announcements->{$_->{'user'}};
    push(@{$announcements->{$_->{'user'}}}, {
        comment => $_->{'comment'},
        change => $change,
        title => $_->{'title'},
        type => $_->{'type'},
        date => timeDifference($_->{'timestamp'})});
  }

  for my $user (sort keys %{$announcements})
  {
    my $total = scalar(@{$announcements->{$user}});
    my $count = 0;

    say(BLACK.BOLD."[".PURPLE."UnvWiki".BLACK."] ".WHITE.BOLD. $user . NORMAL." made $total new " . ($total == 1 ? "change" : "changes") . "...\n");
    for (@{$announcements->{$user}})
    {
      if ($count == 4 && $total > $count)
      {
        say(" ... +" .BOLD.WHITE.($total-$count) . " more!\n");
        last;
      }
      my $color = RED;
      my $action = "created";

      $color = GREEN if $_->{'change'} > 0;
      $action= "edited" if $_->{'type'} && $_->{'type'} eq "edit";
      $action = "deleted" if $_->{'change'} == 0 && $_->{'type'} eq "log";
      say(NORMAL. " " . $action . " " .BOLD. $_->{'title'} . ": ".NORMAL . ( $_->{'comment'} ? $_->{'comment'} : "<none>...") . $_->{'date'} . "\n");
      $count++;
    }
  }

  $lasttime = intifyDate($data[0]->{'timestamp'});
  $_[KERNEL]->delay( pollWiki => 120 );
}

sub say
{
  foreach (@channels)
  {
    $irc->yield(privmsg => $_, $_[0]);
  }
}

sub intifyDate
{
  my ($a) = @_;
  return 0 unless $a;
  unless ($a =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$/)
  {
    return 0;
  }
  my ($year, $month, $date, $hour, $min, $sec) = ($1, $2, $3, $4, $5, $6);
  return "$year$month$date$hour$min$sec";
}

sub timeDifference
{
  my ($a) = @_;
  return 0 unless $a;
  unless ($a =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$/)
  {
    return 0;
  }
  my ($year2, $month2, $date2, $hour2, $min2, $sec2) = ($1, $2, $3, $4, $5, $6);
  my ($year1, $month1, $date1, $hour1, $min1, $sec1) = Gmtime();

  my ($year, $month, $date, $hour, $min, $sec) = N_Delta_YMDHMS($year1, $month1, $date1, $hour1, $min1, $sec1,
                                  $year2, $month2, $date2, $hour2, $min2, $sec2);

  return format_date($year, "year") if $year;
  return format_date($month, "month") if $month;
  return format_date($date, "day") if $date;
  return format_date($hour, "hour") if $hour;
  return format_date($min, "minute") if $min;
  return format_date($sec, "second");
}

sub format_date
{
  my ($in, $type) = @_;
  my ($start, $end, $suffix) = ("", "", "");
  unless (abs($in) == 1)
  {
    $suffix = "s";
  }
  if ($in < 0)
  {
    $end = " ago";
  }
  else
  {
    $start = "in ";
  }

  return $start . abs($in) . " $type" . $suffix . "$end";
}
