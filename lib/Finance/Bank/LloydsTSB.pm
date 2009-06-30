package Finance::Bank::LloydsTSB;

=head1 NAME

Finance::Bank::LloydsTSB - Check your bank accounts from Perl

=head1 SYNOPSIS

  use Finance::Bank::LloydsTSB;
  my @accounts = Finance::Bank::LloydsTSB->check_balance(
        username  => $username,
        password  => $password
        memorable => $memorable_phrase
  );
  for my $acc (@accounts) {
    printf "%20s : %8s / %19s : GBP %9.2f\n",
      $acc->name, ($acc->sort_code || ''), $acc->account_no, $acc->balance;
  }
  my $statement = $accounts[0]->fetch_statement;

  # Retrieve QIF for all transactions in January 2008.
  my $qif = $accounts[1]->download_statement(2008, 01, 01, 5);

=head1 DESCRIPTION

This module provides a rudimentary interface to the LloydsTSB online
banking system at C<https://online.lloydstsb.co.uk/>. You will need
either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed for HTTPS
support to work with LWP.

=cut

use strict;
use warnings;

use Carp;

our $VERSION = '1.31';
our $DEBUG = 0;

use Carp qw(carp cluck croak confess);
use HTML::TableExtract qw(tree);
use WWW::Mechanize;

use Finance::Bank::LloydsTSB::utils qw(debug trim);
use Finance::Bank::LloydsTSB::Account;

our $ua = WWW::Mechanize->new(
    env_proxy => 1, 
    keep_alive => 1, 
    timeout => 30,
); 

=head1 CLASS METHODS

=cut

sub _login {
    my $self = shift;

    $ua->get("https://online.lloydstsb.co.uk/customer.ibc");
    my $field = $ua->current_form->find_input("UserId1");
    $field->{type}="input";
    bless $field, "HTML::Form::TextInput";
    $ua->field(UserId1  => $self->{username});
    $ua->field(Password => $self->{password});
    $ua->click;

    # Now we're at the new "memorable information" page, so parse that
    # and input the right form data.

    for (0..2) {
        my $key;
        eval { $key = $ua->current_form->find_input("ResponseKey$_")->value; };
        croak "Couldn't log in; check your password and username" if $@;
        my $value = substr(lc $self->{memorable}, $key-1, 1);
        $ua->field("ResponseValue$_" => $value);
    }

    $ua->click;
}

=head2 get_accounts(username => $u, password => $p, memorable => $m)

Return a list of Finance::Bank::LloydsTSB::Account objects, one for
each of your bank accounts.

=cut

sub get_accounts {
    my ($class, %opts) = @_;
    croak "Must provide a password" unless exists $opts{password};
    croak "Must provide a username" unless exists $opts{username};
    croak "Must provide memorable information" unless exists $opts{memorable};

    my $self = bless { %opts }, $class;

    $self->_login;

    if ($ua->content =~ /To suppress a message/i) {
        warn "Got messages screen; clicking through ...\n";
        $ua->click;
    }

    croak "Failed memorable info stage:", $ua->content
      unless $ua->content =~ /Account\s+list/i;

    # Now we have the account list page; we need to parse it.
    my $te = new HTML::TableExtract(
        headers => [
            "Account name",
            "Balance",
            "O/D Limit",
            "Options",
        ],
        # Only use keep_html if extraction mode is raw text/HTML
        # i.e. subclass of HTML::Parser!  Otherwise there seems to be
        # a bug which includes start tag in the text segment.
        # keep_html => 1,
    );
    my $html = $ua->content;
    $html =~ s/&nbsp;?/ /g;
    $te->parse($html);
    my @tables = $te->tables;
    croak "HTML::TableExtract failed to find table" unless @tables;
    croak "HTML::TableExtract found >1 tables" unless @tables == 1;

    my @accounts;

    my $acc_action_forms = $class->_get_acc_action_form_mapping;

    # Assume only one matching table using $te->rows shorthand
    foreach my $row ($te->rows) {
        my ($descr, $balance, $OD_limit, $options) =
          map { $class->trim($_) } @$row;
        # Grr!!  Sometimes $balance ends up being a scalar reference?!
        next unless ref($balance) =~ /^HTML::/
#                and $balance->can('find_by_attribute')
                and $balance->find_by_attribute('class', 'prodDetail');
        my $link = $descr->find('a');
        my $name = $link->as_text;
        my $num = $class->trim($link->right->right);
        croak "Couldn't parse sort code and a/c number in '$num'"
          unless $num =~ /^(\d\d-\d\d-\d\d) (\d{6,10})$/;
        my ($sort_code, $account_no) = ($1, $2);

        
        my $terse_num = "$sort_code$account_no";
        $terse_num =~ tr/-//d;
        my $form_index = $acc_action_forms->{$terse_num};
        if (exists $acc_action_forms->{$terse_num}) {
            $class->debug("Found form index $form_index for $terse_num\n");
        }
        else {
            die "Couldn't figure out form index for $terse_num";            
        }

        push @accounts, (bless {
            ua         => $ua,
            name       => $name,
            sort_code  => $sort_code,
            account_no => $account_no,
            balance    => $class->normalize_balance($balance->as_trimmed_text),

            # what's this one for?
            parent     => $self,

            # $options ISA HTML::ElementTable::DataElement
            #    which ISA HTML::ElementTable::Element
            #    which ISA HTML::ElementSuper
            #    which ISA HTML::Element
            # $options->position gives us (x,y) of cell within table
            # $options->tree gives us the containing HTML::ElementTable
#            options    => $options,
            form_index => $form_index || undef
        }, "Finance::Bank::LloydsTSB::Account");
    }
    return @accounts;
}

sub _get_acc_action_form_mapping {
    my $class = shift;

    # WWW::Mechanize only lets us select forms by name or number, but
    # the account action forms don't have a unique name, so we need a
    # way of mapping between an account and its number as appearing
    # sequentially on the page.
    my %acc_action_forms;
    my @forms = ('WWW::Mechanize::form_number counts from 1', $ua->forms);
    $class->debug("Found $#forms forms on page\n");
    foreach my $i (1 .. $#forms) {
        my $form = $forms[$i];
        # using HTML::Form
        unless (($form->attr('class') || '') eq 'acc_action_form') {
            $class->debug("Form $i is not an acc_action_form\n");
            next;
        }
        my $input = $form->find_input('Account', 'hidden');
        die "no hidden 'Account' input found" unless $input;
        my $num = $input->value; # this should be sortcode + acc #, no punctuation
        $acc_action_forms{$num} = $i;
        $class->debug("Form with hidden 'Account' input '$num' is number $i\n");
    }
    return \%acc_action_forms;
}

=head2 normalize_balance($balance)

Converts the website's textual representation of a balance sum into
numeric form.

=cut

sub normalize_balance {
    my $class = shift;
    my ($balance) = @_;
    $balance = '0' if $balance eq 'Nil';
    $balance =~ s/ CR//;
    $balance = "-$balance" if $balance =~ s/ DR//;
    return $balance;
}

=head2 logoff()

Logs off, if you want to be nice and not bloat the sessions table they
no doubt have in their backend database.

=cut

sub logoff {
    my $class = shift;
    return unless $ua;
    if ($ua->follow_link( text_regex => qr/Logoff/ )) {
        $class->debug("Logged off\n");
    }
}

1;


=head1 ACCOUNT OBJECT METHODS

=over 4

=item * $ac->name

=item * $ac->sort_code

=item * $ac->account_no


Return the name of the account, the sort code formatted as the familiar
XX-YY-ZZ, and the account number.

=item * $ac->balance

Return the balance as a signed floating point value.

=item * $ac->statement

Return a mini-statement as a line-separated list of transactions.
Each transaction is a comma-separated list. B<WARNING>: this interface
is currently only useful for display, and hence may change in later
versions of this module.

=back

=head1 WARNING

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 AUTHORS

Original by Simon Cozens C<simon@cpan.org>

Improvements by Adam Spiers <aspiers@cpan.org>

=cut

