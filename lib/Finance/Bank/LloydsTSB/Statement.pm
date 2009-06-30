package Finance::Bank::LloydsTSB::Statement;

use strict;
use warnings;

sub transactions { shift->{transactions} }
sub start_date   { shift->{start_date}   }
sub end_date     { shift->{end_date}     }

1;
