#!/usr/bin/perl
use strict;

# Открываем файл для записи результатов
open(my $out_fh, '>', 'CALL_result.txt') or die "Cannot open output.txt: $!";
 
my $event;
my %actions = (
    'CALL' => [
{
   'action' => sub {
my ($event) =@_;
my ($date, $garbage) = split /,CALL/, $event;
 
$date =~ s/\d\d:\d\d\.\d+-//g;
 
my ($garbage, $context) = split /Context=/, $event;
my ($context, $garbage) = split /,Interface=/, $context;
 
if ($context =~ /\n/) {
   my @mlc = split /\n/, $context;
   $context = $mlc[$#mlc];
}
 
my $result = "$date-$context\n";
print $result if $context;
print $out_fh $result if $context;  # Записываем в файл
    },
},
    ],
);
 
print "\n";
while (<>) {
    $event=process_event($event) if /^\d\d:\d\d\.\d+/;
    $event .= $_;
}
 
sub process_event($) {
    my ($event) = @_;
    return unless $event;
    foreach my $event_type ( keys %actions ) {
next unless $event =~ /^[^,]+,$event_type,/;
foreach my $issue ( @{ $actions{$event_type} }) {
   &{$issue->{action}}($event);
}
    }
}

# Закрываем файл при завершении
close($out_fh);