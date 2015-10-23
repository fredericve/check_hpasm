package HP::Proliant::Component::AsrSubsystem::CLI;
our @ISA = qw(HP::Proliant::Component::AsrSubsystem);

use strict;
use constant { OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3 };

sub init {
  my $self = shift;
  my %params = @_;
}

sub overall_check {
  my $self = shift;
  my %params = @_;
}

1;
