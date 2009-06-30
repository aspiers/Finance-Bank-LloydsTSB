package Finance::Bank::LloydsTSB;
use strict;
use Carp;
our $VERSION = '1.2';
use WWW::Mechanize;
our $ua = WWW::Mechanize->new(
    env_proxy => 1, 
    keep_alive => 1, 
    timeout => 30,
); 

sub check_balance {
    my ($class, %opts) = @_;
    croak "Must provide a password" unless exists $opts{password};
    croak "Must provide a username" unless exists $opts{username};
    croak "Must provide memorable information" unless exists $opts{memorable};

    my $self = bless { %opts }, $class;

    $ua->get("https://online.lloydstsb.co.uk/customer.ibc");
    my $field = $ua->current_form->find_input("UserId1");
    $field->{type}="input";
    bless $field, "HTML::Form::TextInput";
    $ua->field(UserId1  => $opts{username});
    $ua->field(Password => $opts{password});
    $ua->click;

    # Now we're at the new "memorable information" page, so parse that
    # and input the right form data.

    for (0..2) {
        my $key;
        eval { $key = $ua->current_form->find_input("ResponseKey$_")->value; };
        croak "Couldn't log in; check your password and username" if $@;
        my $value = substr(lc $opts{memorable}, $key-1, 1);
        $ua->field("ResponseValue$_" => $value);
    }

    my $response = $ua->click;
    $ua->get($response->{_headers}->{location});

    # Now we have the data, we need to parse it.

    my $foo = new TableThing;
    $foo->parse($ua->content);

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
        $balance = "-$balance" if $balance =~ s/ DR//;
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
    $Finance::Bank::LloydsTSB::ua->get("https://online.lloydstsb.co.uk/statement.ibc?Account=$code");
    $Finance::Bank::LloydsTSB::ua->get("https://online.lloydstsb.co.uk/statment.stm?Account=$code");
    return $ua->content;
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
        username  => $username,
        password  => $password
        memorable => $memorable_phrase )) {
      printf "%20s : %8s / %8s : GBP %9.2f\n", 
             $_->name, $_->sort_code, $_->account_no, $_->balance;
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to the LloydsTSB online
banking system at C<https://online.lloydstsb.co.uk/>. You will need
either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed for HTTPS
support to work with LWP.

=head1 CLASS METHODS

    check_balance(username => $u, password => $p, memorable => $m)

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

