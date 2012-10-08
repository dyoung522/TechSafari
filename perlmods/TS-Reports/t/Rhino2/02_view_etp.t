

use strict;
use warnings;

use Excel::Template::Plus;



Excel::Template::Plus->new(
    engine   => 'TT',
    template => 'canned/report.xls.tt',
    config   => { INCLUDE => "C:\\charlie\\src\\TS-Reports\\view", },
    params   => {},    
);  




  