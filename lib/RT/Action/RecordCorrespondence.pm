# BEGIN LICENSE BLOCK
# 
# Copyright (c) 1996-2003 Jesse Vincent <jesse@bestpractical.com>
# 
# (Except where explictly superceded by other copyright notices)
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# Unless otherwise specified, all modifications, corrections or
# extensions to this work which alter its source code become the
# property of Best Practical Solutions, LLC when submitted for
# inclusion in the work.
# 
# 
# END LICENSE BLOCK
#
package RT::Action::RecordCorrespondence;
require RT::Action::Generic;
use strict;
use vars qw/@ISA/;
@ISA = qw(RT::Action::Generic);

=head1 NAME

RT::Action::RecordCorrespondence - An Action which can be used from an
external tool, or in any situation where a ticket transaction has not
been started, to make a comment on the ticket.

=head1 SYNOPSIS

my $action_obj = RT::Action::RecordCorrespondence->new(
			'TicketObj'   => $ticket_obj,
			'TemplateObj' => $template_obj,
			);
my $result = $action_obj->Prepare();
$action_obj->Commit() if $result;

=head1 METHODS

=head2 Prepare

Check for the existence of a Transaction.  If a Transaction already
exists, and is of type "Comment" or "Correspond", abort because that
will give us a loop.

=cut


sub Prepare {
    my $self = shift;
    if (defined $self->{'TransactionObj'} &&
	$self->{'TransactionObj'}->Type =~ /^(Comment|Correspond)$/) {
	return undef;
    }
    return 1;
}

=head2 Commit

Create a Transaction by calling the ticket's Correspond method on our
parsed Template, which may have an RT-Send-Cc or RT-Send-Bcc header.
The Transaction will be of type Correspond.  This Transaction can then
be used by the scrips that actually send the email.

=cut

sub Commit {
    my $self = shift;
    $self->CreateTransaction();
}

sub CreateTransaction {
    my $self = shift;

    my ($result, $msg) = $self->{'TemplateObj'}->Parse(
	TicketObj => $self->{'TicketObj'});
    return undef unless $result;
    
    my ($trans, $desc, $transaction) = $self->{'TicketObj'}->Correspond(
	MIMEObj => $self->TemplateObj->MIMEObj);
    $self->{'TransactionObj'} = $transaction;
}
    

eval "require RT::Action::RecordCorrespondence_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Action/RecordCorrespondence_Vendor.pm});
eval "require RT::Action::RecordCorrespondence_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Action/RecordCorrespondence_Local.pm});

1;
