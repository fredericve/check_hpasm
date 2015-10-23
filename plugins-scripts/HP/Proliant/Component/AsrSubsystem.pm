package HP::Proliant::Component::AsrSubsystem;
our @ISA = qw(HP::Proliant::Component);

use strict;
use constant { OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3 };

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    runtime => $params{runtime},
    rawdata => $params{rawdata},
    method => $params{method},
    condition => $params{condition},
    status => $params{status},
    temperatures => [],
    blacklisted => 0,
    info => undef,
    extendedinfo => undef,
    base_oids => {
        cpqHeAsr            => "1.3.6.1.4.1.232.6.2.5",
        cpqHeAsrStatus      => "1.3.6.1.4.1.232.6.2.5.1.0",
        cpqHeAsrCondition   => "1.3.6.1.4.1.232.6.2.5.17.0",
    },
  };
  if ($self->{method} eq 'snmp') {
    bless $self, "HP::Proliant::Component::AsrSubsystem::SNMP";
  } elsif ($self->{method} eq 'cli') {
    bless $self, "HP::Proliant::Component::AsrSubsystem::CLI";
  } else {
    die "unknown method";
  }
  return $self;
}

sub check {
  my $self = shift;
  my $errorfound = 0;
  $self->add_info('checking ASR');
  $self->overall_check(); 
}

sub dump {
  my $self = shift;
}

1;

