package HP::Proliant;

use strict;
use constant { OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3 };
use Data::Dumper;

our @ISA = qw(HP::Server);

sub init {
  my $self = shift;
  $self->{components} = {
      powersupply_subsystem     => HP::Proliant::Component::PowersupplySubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      fan_subsystem             => HP::Proliant::Component::FanSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      temperature_subsystem     => HP::Proliant::Component::TemperatureSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      cpu_subsystem             => HP::Proliant::Component::CpuSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      memory_subsystem          => HP::Proliant::Component::MemorySubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      nic_subsystem             => HP::Proliant::Component::NicSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      disk_subsystem            => HP::Proliant::Component::DiskSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      asr_subsystem             => HP::Proliant::Component::AsrSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
      event_subsystem           => HP::Proliant::Component::EventSubsystem->new(
        method      => $self->{method},
        runtime     => $self->{runtime}),
  };
  $self->{serial} = 'unknown';
  $self->{product} = 'unknown';
  $self->{romversion} = 'unknown';
  my $rawdata = $self->collect();
  if (! $self->{runtime}->{plugin}->check_messages() && 
      ! exists $self->{noinst_hint}) {
    $self->set_serial();
    $self->check_for_buggy_firmware();
    $self->analyze_cpus();
    foreach my $component (keys(%{$self->{components}})) {
      if (! $component->skipped()){
        $component->analyze_subsystem($rawdata);
      }
    }
    $self->auto_blacklist();
    foreach my $component (keys(%{$self->{components}})) {
      if (! $component->skipped()){
        $component->check_subsystem();
      }
    }
  }
}

sub identify {
  my $self = shift;
  foreach (qw(product serial romversion)) {
    $self->{$_} =~ s/^\s+//;
    $self->{$_} =~ s/\s+$//;
  }
  return sprintf "System: '%s', S/N: '%s', ROM: '%s'", 
      $self->{product}, $self->{serial}, $self->{romversion};
}

sub check_for_buggy_firmware {
  my $self = shift;
  my @buggyfirmwares = (
      "P24 12/11/2001",
      "P24 11/15/2002",
      "D13 06/03/2003",
      "D13 09/15/2004",
      "P20 12/17/2002"
  );
  if ($self->{romversion} =~ /^\w+ \d+\/\d+\/\d+$/) {
    $self->{runtime}->{options}->{buggy_firmware} =
        grep /^$self->{romversion}/, @buggyfirmwares;
  } else {
    # nicht parsbarer schrott in cpqSeSysRomVer, gesehen bei Gen9
    $self->{runtime}->{options}->{buggy_firmware} = undef;
  }
}

sub dump {
  my $self = shift;
  printf STDERR "serial %s\n", $self->{serial};
  printf STDERR "product %s\n", $self->{product};
  printf STDERR "romversion %s\n", $self->{romversion};
  printf STDERR "%s\n", Data::Dumper::Dumper($self->{components});
}

sub auto_blacklist() {
  my $self = shift;
  if ($self->{product} =~ /380 g6/) {
    # http://bizsupport1.austin.hp.com/bc/docs/support/SupportManual/c01723408/c01723408.pdf seite 19
    if ($self->{components}->{cpu_subsystem}->num_cpus() == 1) {
      $self->add_blacklist('ff/f:5,6');
    }
  } elsif ($self->{product} =~ /380 g6/) {
    # http://bizsupport1.austin.hp.com/bc/docs/support/SupportManual/c01704762/c01704762.pdf Fan 2 is only required when processor 2 is installed in the server.
  }
}


package HP::Proliant::CLI;

use strict;
use constant { OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3 };

our @ISA = qw(HP::Proliant);

sub collect {
  my $self = shift;
  my $hpasmcli = undef;
  if (($self->{runtime}->{plugin}->opts->hpasmcli) &&
      (-f $self->{runtime}->{plugin}->opts->hpasmcli) &&
      (! -x $self->{runtime}->{plugin}->opts->hpasmcli)) {
    no strict 'refs';
    open(BIRK, $self->{runtime}->{plugin}->opts->hpasmcli);
    # all output in one file prefixed with server|powersupply|fans|temp|dimm
    while(<BIRK>) {
      chomp;
      $self->{rawdata} .= $_."\n";
    }
    close BIRK;
    # If you run this script and redirect it's output to a file
    # you can use it for testing purposes with
    # --hpasmcli <output>
    # It must not be executable. (chmod 644)
    my $diag = <<'EOEO';
    hpasmcli=$(which hpasmcli)
    hpacucli=$(which hpacucli)
    for i in server powersupply fans temp dimm
    do
      $hpasmcli -s "show $i" | while read line
      do
        printf "%s %s\n" $i "$line"
      done
    done 
    if [ -x "$hpacucli" ]; then
      for i in config status
      do
        $hpacucli ctrl all show $i | while read line
        do
          printf "%s %s\n" $i "$line"
        done
      done
    fi
EOEO
  } else {
    #die "exec hpasmcli";
    # alles einsammeln und in rawdata stecken
    my $hpasmcli = undef;
    $hpasmcli = $self->{runtime}->{plugin}->opts->hpasmcli ?
        $self->{runtime}->{plugin}->opts->hpasmcli : '/sbin/hpasmcli';
# check if this exists at all
# descend the directory
    if ($self->{runtime}->{plugin}->opts->hpasmcli &&
        -e $self->{runtime}->{plugin}->opts->hpasmcli) {
      $hpasmcli = $self->{runtime}->{plugin}->opts->hpasmcli;
    } elsif (-e '/sbin/hpasmcli') {
      $hpasmcli = '/sbin/hpasmcli';
    } else {
      $hpasmcli = undef;
    }
    if ($hpasmcli) {
      if ($< != 0) {
        close STDIN;
        $hpasmcli = "sudo -S ".$hpasmcli;
      }
      $self->trace(2, sprintf "calling %s\n", $hpasmcli);
      $self->check_daemon();
      if (! $self->{runtime}->{plugin}->check_messages()) {
        $self->check_hpasm_client($hpasmcli);
        if (! $self->{runtime}->{plugin}->check_messages()) {
          foreach my $component (qw(server fans temp dimm powersupply iml)) {
            if (open HPASMCLI, "$hpasmcli -s \"show $component\" </dev/null |") {
              my @output = <HPASMCLI>;
              close HPASMCLI;
              $self->{rawdata} .= join("\n", map {
                  $component.' '.$_;
              } @output);
            }
          }
          if ($self->{runtime}->{options}->{hpacucli}) {
            #1 oder 0. pfad selber finden
            my $hpacucli = undef;
            if (-e '/usr/sbin/hpacucli') {
              $hpacucli = '/usr/sbin/hpacucli';
            } elsif (-e '/usr/local/sbin/hpacucli') {
              $hpacucli = '/usr/local/sbin/hpacucli';
            } else {
              $hpacucli = $hpasmcli;
              $hpacucli =~ s/^sudo\s*//;
              $hpacucli =~ s/hpasmcli/hpacucli/;
              $hpacucli = -e $hpacucli ? $hpacucli : undef;
            }
            if ($hpacucli) {
              if ($< != 0) {
                close STDIN;
                $hpacucli = "sudo -S ".$hpacucli;
              }
              $self->trace(2, sprintf "calling %s\n", $hpacucli);
              $self->check_hpacu_client($hpacucli);
              if (! $self->{runtime}->{plugin}->check_messages()) {
                if (open HPACUCLI, "$hpacucli ctrl all show status 2>&1|") {
                  my @output = <HPACUCLI>;
                  close HPACUCLI;
                  $self->{rawdata} .= join("\n", map {
                      'status '.$_;
                  } @output);
                }
                if (open HPACUCLI, "$hpacucli ctrl all show config 2>&1|") {
                  my @output = <HPACUCLI>;
                  close HPACUCLI;
                  $self->{rawdata} .= join("\n", map {
                      'config '.$_;
                  } @output);
                  if (grep /Syntax error at "config"/, @output) {
                    # older version of hpacucli CLI 7.50.18.0
                    foreach my $slot (0..10) {
                      if (open HPACUCLI, "$hpacucli ctrl slot=$slot logicaldrive all show 2>&1|") {
                        my @output = <HPACUCLI>;
                        close HPACUCLI;
                        $self->{rawdata} .= join("\n", map {
                            'config '.$_;
                        } @output);
                      }
                      if (open HPACUCLI, "$hpacucli ctrl slot=$slot physicaldrive all show 2>&1|") {
                        my @output = <HPACUCLI>;
                        close HPACUCLI;
                        $self->{rawdata} .= join("\n", map {
                            'config '.$_;
                        } @output);
                      }
                    }
                  }
                }
              } elsif ($self->{runtime}->{options}->{hpacucli} == 2) {
                # we probably don't have sudo-privileges, but we were compiled with
                # --enable-hpacucli=maybe
                # so we cover it up in silence
                $self->remove_message(UNKNOWN);
                $self->trace(2, sprintf "calling %s seems to have failed, but nobody cares\n", $hpacucli);
              }
            } else {
              if ($self->{runtime}->{options}->{noinstlevel} eq 'ok') {
                $self->add_message(OK,
                    'hpacucli is not installed. let\'s hope the best...');
              } else {
                $self->add_message(
                    uc $self->{runtime}->{options}->{noinstlevel},
                    'hpacucli is not installed.');
              }
            }
          }
        }
      }
    } else {
      if ($self->{runtime}->{options}->{noinstlevel} eq 'ok') {
        $self->add_message(OK,
            'hpasm is not installed, i can only guess');
        $self->{noinst_hint} = 1;
      } else {
        $self->add_message(
            uc $self->{runtime}->{options}->{noinstlevel},
            'hpasmcli is not installed.');
      }
    }
  }
}


sub check_daemon {
  my $self = shift;
  my $multiproc_os_signatures_files = {
      '/etc/SuSE-release' => 'VERSION\s*=\s*8',
      '/etc/trustix-release' => '.*',
      '/etc/redhat-release' => '.*Pensacola.*',
      '/etc/debian_version' => '3\.1',
      '/etc/issue' => '.*Kernel 2\.4\.9-vmnix2.*', # VMware ESX Server 2.5.4
  };
  if (open PS, "/bin/ps -e -ocmd|") {
    my $numprocs = 0;
    my $numcliprocs = 0;
    my @procs = <PS>;
    close PS;
    $numprocs = grep /hpasm.*d$/, map { (split /\s+/, $_)[0] } @procs;
    $numcliprocs = grep /hpasmcli/, grep !/check_hpasm/, @procs;
    if (! $numprocs ) {
      $self->add_message(CRITICAL, 'hpasmd needs to be restarted');
    } elsif ($numprocs > 1) {
      my $known = 0;
      foreach my $osfile (keys %{$multiproc_os_signatures_files}) {
        if (-f $osfile) {
          open OSSIG, $osfile;
          if (grep /$multiproc_os_signatures_files->{$osfile}/, <OSSIG>) {
            $known = 1;
          }
          close OSSIG;
        }
      }
      if (! $known) {
        $self->add_message(UNKNOWN, 'multiple hpasmd procs');
      }
    }
    if ($numcliprocs == 1) {
      $self->add_message(UNKNOWN, 'another hpasmcli is running');
    } elsif ($numcliprocs > 1) {
      $self->add_message(UNKNOWN, 'hanging hpasmcli processes');
    }
  }
}

sub check_hpasm_client {
  my $self = shift;
  my $hpasmcli = shift;
  if (open HPASMCLI, "$hpasmcli -s help 2>&1 |") {
    my @output = <HPASMCLI>;
    close HPASMCLI;
    if (grep /Could not communicate with hpasmd/, @output) {
      $self->add_message(CRITICAL, 'hpasmd needs to be restarted');
    } elsif (grep /(asswor[dt]:)|(You must be root)/, @output) {
      $self->add_message(UNKNOWN,
          sprintf "insufficient rights to call %s", $hpasmcli);
    } elsif (grep /must have a tty/, @output) {
      $self->add_message(CRITICAL,
          'sudo must be configured with requiretty=no (man sudo)');
    } elsif (! grep /CLEAR/, @output) {
      $self->add_message(UNKNOWN,
          sprintf "insufficient rights to call %s", $hpasmcli);
    }
  } else {
    $self->add_message(UNKNOWN,
        sprintf "insufficient rights to call %s", $hpasmcli);
  }
}

sub check_hpacu_client {
  my $self = shift;
  my $hpacucli = shift;
  if (open HPACUCLI, "$hpacucli help 2>&1 |") {
    my @output = <HPACUCLI>;
    close HPACUCLI;
    if (grep /Another instance of hpacucli is running/, @output) {
      $self->add_message(UNKNOWN, 'another hpacucli is running');
    } elsif (grep /You need to have administrator rights/, @output) {
      $self->add_message(UNKNOWN,
          sprintf "insufficient rights to call %s", $hpacucli);
    } elsif (grep /(asswor[dt]:)|(You must be root)/, @output) {
      $self->add_message(UNKNOWN,
          sprintf "insufficient rights to call %s", $hpacucli);
    } elsif (! grep /(CLI Syntax)|(ACU CLI)/, @output) {
      $self->add_message(UNKNOWN,
          sprintf "insufficient rights to call %s", $hpacucli);
    }
  } else {
    $self->add_message(UNKNOWN,
        sprintf "insufficient rights to call %s", $hpacucli);
  }
}

sub set_serial {
  my $self = shift;
  foreach (grep(/^server/, split(/\n/, $self->{rawdata}))) {
    if (/System\s+:\s+(.*[^\s])/) {
      $self->{product} = lc $1;
    } elsif (/Serial No\.\s+:\s+(\w+)/) {
      $self->{serial} = $1;
    } elsif (/ROM version\s+:\s+(.*[^\s])/) {
      $self->{romversion} = $1;
    }
  }
  $self->{serial} = $self->{serial};
  $self->{product} = lc $self->{product};
  $self->{romversion} = $self->{romversion};
  foreach (qw(serial product romversion)) {
    $self->{$_} =~ s/\s+$//g;
  }
}


package HP::Proliant::SNMP;

use strict;
use constant { OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3 };

our @ISA = qw(HP::Proliant);

sub collect {
  my $self = shift;
  my %oidtables = (
      system =>            "1.3.6.1.2.1.1",
      cpqSeRom =>          "1.3.6.1.4.1.232.1.2.6",
  );
  my %componentoids = (
      #    cpqHeComponent =>  "1.3.6.1.4.1.232.6.2",
      #    cpqHeFComponent => "1.3.6.1.4.1.232.6.2.6.7",
      #    cpqHeTComponent => "1.3.6.1.4.1.232.6.2.6.8",
  );

  foreach my $component (keys(%{$self->{components}}) {
      if (! $component->skipped()) {
          foreach my $base_oid (keys(%{$component->{base_oids}}) {
              $oidtables{$base_oid} = $component->{base_oids}->{$base_oid};
          }
      }
  }

  my %oidvalues = (
  );
  if ($self->{runtime}->{plugin}->opts->snmpwalk) {
    my $cpqSeMibCondition = '1.3.6.1.4.1.232.1.1.3.0'; # 2=ok
    my $cpqHeMibCondition = '1.3.6.1.4.1.232.6.1.3.0'; # hat nicht jeder
    if ($self->{productname} =~ /4LEE/) {
      # rindsarsch!
      $self->{rawdata}->{$cpqHeMibCondition} = 0;
    }
    if (! exists $self->{rawdata}->{$cpqHeMibCondition} &&
        ! exists $self->{rawdata}->{$cpqSeMibCondition}) { # vlt. geht doch was
        $self->add_message(CRITICAL,
            'snmpwalk returns no health data (cpqhlth-mib)');
    }
    $self->{fullrawdata} = {};
    %{$self->{fullrawdata}} = %{$self->{rawdata}};
    $self->{rawdata} = {};
    if (! $self->{runtime}->{plugin}->check_messages()) {
      # for a better simulation, only put those oids into 
      # rawdata which would also be put by a real snmp agent.
      foreach my $table (keys %oidtables) {
        my $oid = $oidtables{$table};
        $oid =~ s/\./\\./g;
        my $tmpoids = {};
        my $tic = time;
        map { $tmpoids->{$_} = $self->{fullrawdata}->{$_} }
            grep /^$oid/, %{$self->{fullrawdata}};
        my $tac = time;
        $self->trace(2, sprintf "%03d seconds for walk %s (%d oids)",
            $tac - $tic, $table, scalar(keys %{$tmpoids}));
        map { $self->{rawdata}->{$_} = $tmpoids->{$_} } keys %{$tmpoids};
      }
      my @oids = values %oidvalues;
      map { $self->{rawdata}->{$_} = $self->{fullrawdata}->{$_} } @oids;
    }
  } else {
    my $net_snmp_version = Net::SNMP->VERSION(); # 5.002000 or 6.000000
    #$params{'-translate'} = [
    #  -all => 0x0
    #];
    my ($session, $error) = 
        Net::SNMP->session(%{$self->{runtime}->{snmpparams}});
    if (! defined $session) {
      $self->{plugin}->add_message(CRITICAL, 'cannot create session object');
      $self->trace(1, Data::Dumper::Dumper($self->{runtime}->{snmpparams}));
    } else {
      $session->translate(['-timeticks' => 0]);
      # revMajor is often used for discovery of hp devices
      my $cpqHeMibRev = '1.3.6.1.4.1.232.6.1';
      my $cpqHeMibRevMajor = '1.3.6.1.4.1.232.6.1.1.0';
      my $cpqHeMibCondition = '1.3.6.1.4.1.232.6.1.3.0';
      my $result = $session->get_request(
          -varbindlist => [$cpqHeMibCondition]
      );
      if ($self->{productname} =~ /4LEE/) {
        # rindsarsch!
        $result->{$cpqHeMibCondition} = 0;
      }
      if (!defined($result) || 
          $result->{$cpqHeMibCondition} eq 'noSuchInstance' ||
          $result->{$cpqHeMibCondition} eq 'noSuchObject' ||
          $result->{$cpqHeMibCondition} eq 'endOfMibView') {
        $self->add_message(CRITICAL,
            'snmpwalk returns no health data (cpqhlth-mib)');
        $session->close;
      } else {
        # this is not reliable. many agents return 4=failed
        #if ($result->{$cpqHeMibCondition} != 2) {
        #  $obstacle = "cmapeerstart";
        #}
      }
    }
    if (! $self->{runtime}->{plugin}->check_messages()) {
      # snmp peer is alive
      $self->trace(2, sprintf "Protocol is %s", 
          $self->{runtime}->{snmpparams}->{'-version'});
      $session->translate;
      my $response = {}; #break the walk up in smaller pieces
      foreach my $table (keys %oidtables) {
        my $oid = $oidtables{$table};
        my $tic = time;
        my $tmpresponse = $session->get_table(
            -baseoid => $oid);
        if (scalar (keys %{$tmpresponse}) == 0) {
          $self->trace(2, sprintf "maxrepetitions failed. fallback");
          $tmpresponse = $session->get_table(
              -maxrepetitions => 1,
              -baseoid => $oid);
        }
        my $tac = time;
        $self->trace(2, sprintf "%03d seconds for walk %s (%d oids)",
            $tac - $tic, $table, scalar(keys %{$tmpresponse}));
        map { $response->{$_} = $tmpresponse->{$_} } keys %{$tmpresponse};
      }
      my @oids = values %oidvalues;
      my $tic = time;
      my $tmpresponse = $session->get_request(
          -varbindlist => \@oids,
      );
      my $tac = time;
      $self->trace(2, sprintf "%03d seconds for get various (%d oids)",
          $tac - $tic, scalar(keys %{$tmpresponse}));
      map { $response->{$_} = $tmpresponse->{$_} } keys %{$tmpresponse};
      $session->close();
      $self->{rawdata} = $response;
    }
  }
  return $self->{rawdata};
  #return $self->{runtime}->{plugin}->check_messages();
}

sub set_serial {
  my $self = shift;

  my $cpqSiSysSerialNum = "1.3.6.1.4.1.232.2.2.2.1.0";
  my $cpqSiProductName = "1.3.6.1.4.1.232.2.2.4.2.0";
  my $cpqSeSysRomVer = "1.3.6.1.4.1.232.1.2.6.1.0";
  my $cpqSeRedundantSysRomVer = "1.3.6.1.4.1.232.1.2.6.4.0";

  $self->{serial} = 
      SNMP::Utils::get_object($self->{rawdata}, $cpqSiSysSerialNum);
  $self->{product} =
      SNMP::Utils::get_object($self->{rawdata}, $cpqSiProductName);
  $self->{romversion} =
      SNMP::Utils::get_object($self->{rawdata}, $cpqSeSysRomVer);
  $self->{redundantromversion} =
      SNMP::Utils::get_object($self->{rawdata}, $cpqSeRedundantSysRomVer);
  if ($self->{romversion} && $self->{romversion} =~
      #/(\d{2}\/\d{2}\/\d{4}).*?([ADP]{1}\d{2}).*/) {
      /(\d{2}\/\d{2}\/\d{4}).*?Family.*?([A-Z]{1})(\d+).*/) {
    $self->{romversion} = sprintf("%s%02d %s", $2, $3, $1);
  } elsif ($self->{romversion} && $self->{romversion} =~
      /([ADP]{1}\d{2})\-(\d{2}\/\d{2}\/\d{4})/) {
    $self->{romversion} = sprintf("%s %s", $1, $2);
  } else {
    # fallback if romversion is broken, redundantromversion not
    #.1.3.6.1.4.1.232.1.2.6.1.0 = STRING: "4), Family "
    #.1.3.6.1.4.1.232.1.2.6.3.0 = ""
    #.1.3.6.1.4.1.232.1.2.6.4.0 = STRING: "v1.20 (08/26/2014), Family "
    if ($self->{redundantromversion} && $self->{redundantromversion} =~
        /(\d{2}\/\d{2}\/\d{4}).*?Family.*?([A-Z]{1})(\d+).*/) {
      $self->{romversion} = sprintf("%s%02d %s", $2, $3, $1);
    } elsif ($self->{redundantromversion} && $self->{redundantromversion} =~
        /([ADP]{1}\d{2})\-(\d{2}\/\d{2}\/\d{4})/) {
      $self->{romversion} = sprintf("%s %s", $1, $2);
    }
  }
  if (!$self->{serial} && $self->{romversion}) {
    # this probably is a very, very old server.
    $self->{serial} = "METHUSALEM";
    $self->{runtime}->{scrapiron} = 1;
  }
  $self->{serial} = $self->{serial};
  $self->{product} = lc $self->{product};
  $self->{romversion} = $self->{romversion};
  $self->{runtime}->{product} = $self->{product};
}


1;
