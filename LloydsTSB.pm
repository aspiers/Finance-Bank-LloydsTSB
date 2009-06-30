package Finance::Bank::LloydsTSB;
use strict;
use Carp;
our $VERSION = '1.01';
use LWP::UserAgent;
our $ua = LWP::UserAgent->new(
    env_proxy => 1, 
    keep_alive => 1, 
    timeout => 30,
    cookie_jar=> {},
    agent => "Mozilla/4.0 (compatible; MSIE 5.12; Atari ST)"
); 

sub check_balance {
    my ($class, %opts) = @_;
    croak "Must provide a password" unless exists $opts{password};
    croak "Must provide a username" unless exists $opts{username};

    my $self = bless { %opts }, $class;

    my $orig_r = $ua->get("https://online.lloydstsb.co.uk/customer.ibc");
    croak $orig_r->error_as_HTML unless $orig_r->is_success;

    my $orig = $orig_r->content;
    my $key;

    $orig =~ /name="Key" type="HIDDEN" value="(\d+)"/ 
        or croak "Couldn't parse key!";
    $key = $1;
    my $check = $ua->post("https://online.lloydstsb.co.uk/customer.ibc", {
        Key => $key,
        LOGONPAGE => "LOGONPAGE",
        UserId1 => $opts{username},
        Password => $opts{password},
       });

    # $check currently contains a redirect, but we can't ask LWP to
    # automatically redirect because Lloyds are EVIL EVIL BUGGERS, who change
    # from POST to GET during a redirect, which is against the HTTP/1.1
    # spec and so LWP doesn't support it.

    # So, we send it again as a GET.
    
    $check = $ua->get("https://online.lloydstsb.co.uk/customer.ibc?Password=$opts{password}&UserId1=$opts{username}");

    # Now we have the data, we need to parse it.

    my $foo = new TableThing;
    $foo->parse($check->content);

    # Extracts the HTML table of accounts.
    my @table = @{$foo->{Table}};
    @table = grep { grep { s/\s{2,}//g; /\S/ } @$_ } @table; # Wrah!
    shift @table;
    my @accounts;
    for (@table) {
        s/&nbsp;// for @$_;
        my @line = grep{/\S/} @$_;
        my $balance = pop @line;
        $balance =~ s/ CR//;
        $balance = "-$balance" if $balance =~ s/ DB//;
        push @accounts, (bless {
            balance    => $balance,
            name       => $line[0],
            sort_code  => $line[1],
            account_no => $line[2],
            parent     => $self
        }, "Finance::Bank::LloydsTSB::Account");
    }
    return @accounts;
}

package Finance::Bank::LloydsTSB::Account;
# Basic OO smoke-and-mirrors Thingy
no strict;
sub AUTOLOAD { my $self=shift; $AUTOLOAD =~ s/.*:://; $self->{$AUTOLOAD} }

sub statement {
    my $ac = shift;
    my $code;
    ($code = $ac->sort_code.$ac->account_no) =~ s/\D//g;
    my $stm = $Finance::Bank::LloydsTSB::ua->get("https://online.lloydstsb.co.uk/statement.ibc?Account=$code");
    $stm = $Finance::Bank::LloydsTSB::ua->get("https://online.lloydstsb.co.uk/statment.stm?Account=$code");
    croak unless $stm->is_success;
    return $stm->content;
}


# This code stolen from Jonathan Stowe <gellyfish@gellyfish.com>
    
package TableThing;
use strict;
use vars qw(@ISA $infield $inrecord $intable);
@ISA = qw(HTML::Parser);
require HTML::Parser;

sub start()
{
   my($self,$tag,$attr,$attrseq,$orig) = @_;
   if ($tag eq 'table')
     {
      $self->{Table} = ();
      $intable++;
     }
   if ( $tag eq 'tr' )
     {
       $self->{Row} = ();
       $inrecord++ ;
     }
   if ( $tag eq 'td' )
     {
       $self->{Field} = '';
       $infield++;
     }
}



sub text()
{
   my ($self,$text) = @_;
   if ($intable && $inrecord && $infield )
     {
       $self->{Field} .= $text;
     }
}

sub end()
{
   my ($self,$tag) = @_;
   $intable-- if($tag eq 'table');
   if($tag eq 'td')
    {
     $infield--;
     push @{$self->{Row}},$self->{Field};
    }
   if($tag eq 'tr')
    {
     $infield--;
     push @{$self->{Table}},\@{$self->{Row}};
    }
}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Finance::Bank::LloydsTSB - Check your bank accounts from Perl

=head1 SYNOPSIS

  use Finance::Bank::LloydsTSB;
  for (Finance::Bank::LloydsTSB->check_balance(
        username=> $username,
        password=> $password)) {
      printf "%20s : %8s / %8s : GBP %9.2f\n", 
             $_->name, $_->sort_code, $_->account_no, $_->balance;
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to the LloydsTSB online
banking system at C<https://online.lloydstsb.co.uk/>. You will need
either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed for HTTPS
support to work with LWP. 

=head1 CLASS METHODS

    check_balance(username => $u, password => $p)

Return a list of account objects, one for each of your bank accounts.

=head1 ACCOUNT OBJECT METHODS

    $ac->name
    $ac->sort_code
    $ac->account_no

Return the name of the account, the sort code formatted as the familiar
XX-YY-ZZ, and the account number.

    $ac->balance

Return the balance as a signed floating point value.

    $ac->statement

Return a mini-statement as a line-separated list of transactions.
Each transaction is a comma-separated list. B<WARNING>: this interface
is currently only useful for display, and hence may change in later
versions of this module.

=head1 WARNING

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 AUTHOR

Simon Cozens C<simon@cpan.org>

=cut

