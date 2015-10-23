package HP::Proliant::Component;
our @ISA = qw(HP::Proliant);

sub analyze_subsystem {
    my $self = shift;
    my $rawdata = shift;
    $self->{rawdata} = $rawdata;
    $self->init();
}

sub check_subsystem {
    my $self =shift;
    $self->check();
    $self->dump()
        if $self->{runtime}->{options}->{verbose} >= 2;
}

1;

