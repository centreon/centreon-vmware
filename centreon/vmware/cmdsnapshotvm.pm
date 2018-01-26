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

package centreon::vmware::cmdsnapshotvm;

use base qw(centreon::vmware::cmdbase);

use strict;
use warnings;
use centreon::vmware::common;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(%options);
    bless $self, $class;
    
    $self->{commandName} = 'snapshotvm';
    
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
    foreach my $label (('warning', 'critical')) {
        if (($options{manager}->{perfdata}->threshold_validate(label => $label, value => $options{arguments}->{$label})) == 0) {
            $options{manager}->{output}->output_add(severity => 'UNKNOWN',
                                                    short_msg => "Argument error: wrong value for $label value '" . $options{arguments}->{$label} . "'.");
            return 1;
        }
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
    foreach my $label (('warning', 'critical')) {
        $self->{manager}->{perfdata}->threshold_validate(label => $label, value => $options{arguments}->{$label});
    }
}

sub getSnapshot {
    my ($self, %options) = @_;
    
    # 2012-09-21T14:16:17.540469Z
    my $create_time = Date::Parse::str2time($options{snapshot}->createTime);
    if (!defined($create_time)) {
        $self->{manager}->{output}->output_add(severity => 'UNKNOWN',
                                                short_msg => "Can't Parse date '" . $options{snapshot}->createTime . "' for vm '" . $options{entity}->{name} . "'");
        return;
    }
    
    my $diff_time = time() - $create_time;
    my $days = int($diff_time / 60 / 60 / 24);
    my $exit = $self->{manager}->{perfdata}->threshold_check(value => $diff_time, threshold => [ { label => 'critical', exit_litteral => 'critical' }, { label => 'warning', exit_litteral => 'warning' } ]);
    
    my $prefix_msg = "VM '$options{entity}->{name}'";
    if (defined($self->{display_description}) && defined($options{entity}->{'config.annotation'}) &&
        $options{entity}->{'config.annotation'} ne '') {
        $prefix_msg .= ' [' . centreon::vmware::common::strip_cr(value => $options{entity}->{'config.annotation'}) . ']';
    }
    if (!$self->{manager}->{output}->is_status(value => $exit, compare => 'ok', litteral => 1)) {
        $self->{vm_errors}->{$exit}->{$options{entity}->{name}."/".$options{snapshot}->name} = 1;
        $self->{manager}->{output}->output_add(long_msg => "$prefix_msg snapshot '" . $options{snapshot}->name . "' creation time: " . $options{snapshot}->createTime);
    }

    return if (!defined($options{snapshot}->{'childSnapshotList'}));

    foreach my $child_snapshot (@{$options{snapshot}->{'childSnapshotList'}}) {
        $self->getSnapshot(entity => $options{entity}, snapshot => $child_snapshot);
    }
}

sub run {
    my $self = shift;

    if ($self->{connector}->{module_date_parse_loaded} == 0) {
        $self->{manager}->{output}->output_add(severity => 'UNKNOWN',
                                               short_msg => "Need to install Date::Parse CPAN Module");
        return ;
    }

    my $multiple = 0;
    my $filters = $self->build_filter(label => 'name', search_option => 'vm_hostname', is_regexp => 'filter');
    if (defined($self->{filter_description}) && $self->{filter_description} ne '') {
        $filters->{'config.annotation'} = qr/$self->{filter_description}/;
    }
    
    my @properties = ('snapshot.rootSnapshotList', 'name', 'runtime.connectionState', 'runtime.powerState');
    if (defined($self->{check_consolidation}) == 1) {
        push @properties, 'runtime.consolidationNeeded';
    }
    if (defined($self->{display_description})) {
        push @properties, 'config.annotation';
    }

    my $result = centreon::vmware::common::search_entities(command => $self, view_type => 'VirtualMachine', properties => \@properties, filter => $filters);
    return if (!defined($result));

    my %vm_consolidate = (); 
    if (scalar(@$result) > 1) {
        $multiple = 1;
    }
    if ($multiple == 1) {
        $self->{manager}->{output}->output_add(severity => 'OK',
                                               short_msg => sprintf("All snapshots are ok"));
    } else {
        $self->{manager}->{output}->output_add(severity => 'OK',
                                               short_msg => sprintf("Snapshot(s) OK"));
    }
    foreach my $entity_view (sort { $a->{name} cmp $b->{name} } @$result) {
        next if (centreon::vmware::common::vm_state(connector => $self->{connector},
                                                  hostname => $entity_view->{name}, 
                                                  state => $entity_view->{'runtime.connectionState'}->val,
                                                  status => $self->{disconnect_status},
                                                  nocheck_ps => 1,
                                                  multiple => $multiple) == 0);
    
        next if (defined($self->{nopoweredon_skip}) && 
                 centreon::vmware::common::is_running(power => $entity_view->{'runtime.powerState'}->val) == 0);
    
        if (defined($self->{check_consolidation}) && defined($entity_view->{'runtime.consolidationNeeded'}) && $entity_view->{'runtime.consolidationNeeded'} =~ /^true|1$/i) {
            $vm_consolidate{$entity_view->{name}} = 1;
        }

        next if (!defined($entity_view->{'snapshot.rootSnapshotList'}));
    
        foreach my $snapshot (@{$entity_view->{'snapshot.rootSnapshotList'}}) {
            $self->getSnapshot(entity => $entity_view, snapshot => $snapshot);
        }
    }

    $self->{manager}->{output}->perfdata_add(label => 'num_warning',
                                             value => scalar(keys %{$self->{vm_errors}->{warning}}),
                                             min => 0);
    $self->{manager}->{output}->perfdata_add(label => 'num_critical',
                                             value => scalar(keys %{$self->{vm_errors}->{critical}}),
                                             min => 0);
    if (scalar(keys %{$self->{vm_errors}->{warning}}) > 0) {
        $self->{manager}->{output}->output_add(severity => 'WARNING',
                                               short_msg => sprintf('Snapshots for VM older than %d days: [%s]', ($self->{warning} / 86400), 
                                                                    join('] [', sort keys %{$self->{vm_errors}->{warning}})));
    }
    if (scalar(keys %{$self->{vm_errors}->{critical}}) > 0) {
        $self->{manager}->{output}->output_add(severity => 'CRITICAL',
                                               short_msg => sprintf('Snapshots for VM older than %d days: [%s]', ($self->{critical} / 86400), 
                                                                    join('] [', sort keys %{$self->{vm_errors}->{critical}})));
    }
    if (scalar(keys %vm_consolidate) > 0) {
         $self->{manager}->{output}->output_add(severity => 'CRITICAL',
                                                short_msg => sprintf('VMs need consolidation: [%s]',
                                                                     join('] [', sort keys %vm_consolidate)));
    }
}

1;
