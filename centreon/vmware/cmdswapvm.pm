# Copyright 2015 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets 
# the needs in IT infrastructure and application monitoring for 
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0  
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package centreon::vmware::cmdswapvm;

use base qw(centreon::vmware::cmdbase);

use strict;
use warnings;
use centreon::vmware::common;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(%options);
    bless $self, $class;
    
    $self->{commandName} = 'swapvm';
    
    return $self;
}

sub checkArgs {
    my ($self, %options) = @_;

    if (defined($options{arguments}->{vm_hostname}) && $options{arguments}->{vm_hostname} eq "") {
        $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                                short_msg => "Argument error: vm hostname cannot be null");
        return 1;
    }
    if (defined($options{arguments}->{disconnect_status}) && 
        $options{manager}->{output}->is_litteral_status(status => $options{arguments}->{disconnect_status}) == 0) {
        $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                                short_msg => "Argument error: wrong value for disconnect status '" . $options{arguments}->{disconnect_status} . "'");
        return 1;
    }
    if (defined($options{arguments}->{nopoweredon_status}) && 
        $options{manager}->{output}->is_litteral_status(status => $options{arguments}->{nopoweredon_status}) == 0) {
        $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                                short_msg => "Argument error: wrong value for nopoweredon status '" . $options{arguments}->{nopoweredon_status} . "'");
        return 1;
    }
    if (($options{manager}->{perfdata}->threshold_validate(label => 'warning', value => $options{arguments}->{warning})) == 0) {
       $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                               short_msg => "Argument error: wrong value for warning value '" . $options{arguments}->{warning} . "'.");
       return 1;
    }
    if (($options{manager}->{perfdata}->threshold_validate(label => 'critical', value => $options{arguments}->{critical})) == 0) {
       $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                               short_msg => "Argument error: wrong value for critical value '" . $options{arguments}->{critical} . "'.");
       return 1;
    }
    return 0;
}

sub initArgs {
    my ($self, %options) = @_;
    
    foreach (keys %{$options{arguments}}) {
        $self->{$_} = $options{arguments}->{$_};
    }
    $self->{manager} = centreon::vmware::common::init_response();
    $self->{manager}->{output}->{plugin} = $options{arguments}->{identity};
    $self->{manager}->{perfdata}->threshold_validate(label => 'warning', value => $options{arguments}->{warning});
    $self->{manager}->{perfdata}->threshold_validate(label => 'critical', value => $options{arguments}->{critical});
}

sub run {
    my $self = shift;

    if (!($self->{connector}->{perfcounter_speriod} > 0)) {
        $self->{manager}->{output}->output_add(severity => 'UNKNOWN',
                                               short_msg => "Can't retrieve perf counters");
        return ;
    }

    my $multiple = 0;
    my $filters = $self->build_filter(label => 'name', search_option => 'vm_hostname', is_regexp => 'filter');    
    if (defined($self->{filter_description}) && $self->{filter_description} ne '') {
        $filters->{'config.annotation'} = qr/$self->{filter_description}/;
    }
    
    my @properties = ('name', 'runtime.connectionState', 'runtime.powerState');
    if (defined($self->{display_description})) {
        push @properties, 'config.annotation';
    }
    
    my $result = centreon::vmware::common::search_entities(command => $self, view_type => 'VirtualMachine', properties => \@properties, filter => $filters);
    return if (!defined($result));
    
    my $values = centreon::vmware::common::generic_performance_values_historic($self->{connector},
                        $result, 
                        [{label => 'mem.swapinRate.average', instances => ['']},
                         {label => 'mem.swapoutRate.average', instances => ['']}],
                        $self->{connector}->{perfcounter_speriod},
                        sampling_period => $self->{sampling_period}, time_shift => $self->{time_shift},
                        skip_undef_counter => 1, multiples => 1, multiples_result_by_entity => 1);
    return if (centreon::vmware::common::performance_errors($self->{connector}, $values) == 1);
    
    if (scalar(@$result) > 1) {
        $multiple = 1;
    }
    if ($multiple == 1) {
        $self->{manager}->{output}->output_add(severity => 'OK',
                                               short_msg => sprintf("All swap rate usages are ok"));
    }
    
    foreach my $entity_view (@$result) {
        next if (centreon::vmware::common::vm_state(connector => $self->{connector},
                                                  hostname => $entity_view->{name}, 
                                                  state => $entity_view->{'runtime.connectionState'}->val,
                                                  power => $entity_view->{'runtime.powerState'}->val,
                                                  status => $self->{disconnect_status},
                                                  powerstatus => $self->{nopoweredon_status},
                                                  multiple => $multiple) == 0);
        my $entity_value = $entity_view->{mo_ref}->{value};    

        # KBps
        my $swap_in = centreon::vmware::common::simplify_number(centreon::vmware::common::convert_number($values->{$entity_value}->{$self->{connector}->{perfcounter_cache}->{'mem.swapinRate.average'}->{'key'} . ":"})) * 1024;
        my $swap_out = centreon::vmware::common::simplify_number(centreon::vmware::common::convert_number($values->{$entity_value}->{$self->{connector}->{perfcounter_cache}->{'mem.swapoutRate.average'}->{'key'} . ":"})) * 1024;

        my $exit1 = $self->{manager}->{perfdata}->threshold_check(value => $swap_in, threshold => [ { label => 'critical', exit_litteral => 'critical' }, { label => 'warning', exit_litteral => 'warning' } ]);
        my $exit2 = $self->{manager}->{perfdata}->threshold_check(value => $swap_out, threshold => [ { label => 'critical', exit_litteral => 'critical' }, { label => 'warning', exit_litteral => 'warning' } ]);
        my $exit = $self->{manager}->{output}->get_most_critical(status => [ $exit1, $exit2 ]);
        my ($swap_in_value, $swap_in_unit) = $self->{manager}->{perfdata}->change_bytes(value => $swap_in);
        my ($swap_out_value, $swap_out_unit) = $self->{manager}->{perfdata}->change_bytes(value => $swap_out);
        
        my $prefix_msg = "'$entity_view->{name}'";
        if (defined($self->{display_description}) && defined($entity_view->{'config.annotation'}) &&
            $entity_view->{'config.annotation'} ne '') {
            $prefix_msg .= ' [' . centreon::vmware::common::strip_cr(value => $entity_view->{'config.annotation'}) . ']';
        }
        
        $self->{manager}->{output}->output_add(long_msg => sprintf("%s Swap In: %s Swap Out: %s", 
                                            $prefix_msg,
                                            $swap_in_value . " " . $swap_in_unit . "/s",
                                            $swap_out_value . " " . $swap_out_unit . "/s"));
        if ($multiple == 0 ||
            !$self->{manager}->{output}->is_status(value => $exit, compare => 'ok', litteral => 1)) {
             $self->{manager}->{output}->output_add(severity => $exit,
                                                    short_msg => sprintf("%s Swap In: %s Swap Out: %s", 
                                            $prefix_msg,
                                            $swap_in_value . " " . $swap_in_unit . "/s",
                                            $swap_out_value . " " . $swap_out_unit . "/s"));
        }
        
        my $extra_label = '';
        $extra_label = '_' . $entity_view->{name} if ($multiple == 1);
        $self->{manager}->{output}->perfdata_add(label => 'swap_in' . $extra_label, unit => 'B',
                                                 value => $swap_in,
                                                 warning => $self->{manager}->{perfdata}->get_perfdata_for_output(label => 'warning'),
                                                 critical => $self->{manager}->{perfdata}->get_perfdata_for_output(label => 'critical'),
                                                 min => 0);
        $self->{manager}->{output}->perfdata_add(label => 'swap_out' . $extra_label, unit => 'B',
                                                 value => $swap_out,
                                                 warning => $self->{manager}->{perfdata}->get_perfdata_for_output(label => 'warning'),
                                                 critical => $self->{manager}->{perfdata}->get_perfdata_for_output(label => 'critical'),
                                                 min => 0);
    }
}

1;
