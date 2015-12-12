=head
# ##################################
# 
# Module : Decrypt.pm
#
# SYNOPSIS
# Decrypt Password
#
# Copyright 2015 eGovernments Foundation
#
#  Log
#  By          	Date        	Change
#  Vasanth KG  	29/11/2015	    Initial Version
#
# #######################################
=cut

# Package name
package Decrypt;

use strict;
use FindBin;

sub getPassword
{
	my ($password) = @_;
	my $KEY = 'eGov_ReleaseSupport_Team_Password_Encryption_key';
	my $cipher = Crypt::CBC->new(
    -key        => $KEY,
    -cipher     => 'Blowfish',
    -padding  => 'space',
    -add_header => 1
    );
    
    my $dec = $cipher->decrypt( deploy::decode_base64( $password ) );
    return $dec;
}
1;