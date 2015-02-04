#!/usr/bin/perl

package SQLWrapper;
use FindBin qw($Bin);
use lib "$Bin";
use Moo;
use Modern::Perl;
use DBI;
	
has 'connectionString', is => 'rw';
has 'user', is => 'rw';
has 'password', is => 'rw'; 
	
sub do {
	my $self = shift;
	
	my ($query) = shift;
	my $dh = DBI->connect($self->connectionString(), $self->user(), $self->password(), { RaiseError => 1 }) or die "DBI error ".$DBI::errstr;

	$dh->do($query) or do { $dh->disconnect(); die "failed to write in database: ".$dh->errstr() };
	$dh->disconnect();
}
	
sub return_all_rows {
	my $self = shift;
	my $dh = DBI->connect($self->connectionString(), $self->user(), $self->password(), { RaiseError => 1 }) or die "DBI error ".$DBI::errstr;
	my $sth = $dh->prepare("SELECT * FROM batdata") or die "Could not prepare sql query: ".$dh->errstr();
	$sth->execute();
		
	my @rows = @{$sth->fetchall_arrayref()};
		
	$sth->finish();
	$dh->disconnect();
	return @rows;
}
		
1;
