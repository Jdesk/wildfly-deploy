=head
# ##################################
# 
# Module : Email.pm
#
# SYNOPSIS
# Send email events on deployment status.
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
package Email;

use strict;
use FindBin;


sub notify_deployment_failure
{
	my ( $logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,$failure_message,$buildnumber, $hostname, $deploy_failure) = @_;
	my $YEAR = `date +%Y`;
	my $DATE = `date`;
	chomp $YEAR;
	chomp $TENANT_NAME;
	chomp $environment;
	$TENANT_NAME="eGov Productization" if ( $TENANT_NAME eq "" );
	$failure_message = "<b>Reason for Failure : </b>".$failure_message;
	my $tmpl = HTML::Template->new( filename => $par_template_dir.'/failed_template.tmpl' );
	$tmpl->param(
   					year     		=> $YEAR,
   					HOSTNAME		=> " on <b>".$hostname."</b>",
   					DEPLOY_FAIL_LOG => $failure_message,
   					deploy_status	=> '<a style="color:#FFFFFF;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:20px;line-height:135%;"><strong>FAILED</strong></a>'
				);
	Email::sendMail("( #".$buildnumber." ) Deployment of ".$TENANT_NAME." failed on ".uc($environment)." environment.",$tmpl->output, $baseConfigFile, $logger,$deploy_failure);

}

sub notify_deployment_success
{
	my ( $logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$API_SCM_HASH,$API_SCM_BRANCH,$api_artifilename,$api_arti_version,$environment,$api_git_url,$buildnumber ) = @_;
	my $YEAR = `date +%Y`;
	my $DATE = `date`;
	chomp $YEAR;
	chomp $TENANT_NAME;
	chomp $environment;
	$TENANT_NAME="eGov Productization" if ( $TENANT_NAME eq "" );
	$api_git_url = `echo $api_git_url | awk -F "\@" '{print \$NF}'| rev | cut -d. -f2- | rev`;	
	$api_git_url =~ s/:/\//g;
	my $tmpl = HTML::Template->new( filename => $par_template_dir.'/success_template.tmpl' );
	$tmpl->param(
   					year     		=> $YEAR,
   					artifact 		=> $api_artifilename,
   					version			=> $api_arti_version,
   					sha				=> "<a href=\"http://".${api_git_url}."/commit/".$API_SCM_HASH."\" target='_blank'>".substr($API_SCM_HASH, 0, 8)."</a>",
   					branch			=> $API_SCM_BRANCH,
   					deploy_status	=> '<a style="color:#FFFFFF;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:20px;line-height:135%;"><strong>SUCCESSFUL</strong></a>'
				);
	Email::sendMail("( #".$buildnumber." ) Deployment of ".$TENANT_NAME." successful on ".uc($environment)." environment.",$tmpl->output, $baseConfigFile, $logger);
}

sub notify_deployment_alert
{
	my ( $logger, $TENANT_NAME, $par_template_dir, $environment, $baseConfigFile, $buildnumber,$JENKINS_URL) = @_;
	
	my $YEAR = `date +%Y`;
	my $DATE = `date`;
	chomp $YEAR;
	chomp $TENANT_NAME;
	$TENANT_NAME="eGov Productization" if ( $TENANT_NAME eq "" );
	my $tmpl = HTML::Template->new( filename => $par_template_dir.'/notify_template.tmpl' );
	$tmpl->param(
   					year     	=> $YEAR,
   					buildnumber => $buildnumber,
   					jenkinsURL	=> $JENKINS_URL,
   					DATE		=> $DATE
				);
	Email::sendMail("Deploying ".$TENANT_NAME." build ( #".$buildnumber." ) to ".uc($environment),$tmpl->output, $baseConfigFile, $logger);
}

#sub notify_deployment_alert
#{
#	my ( $logger, $TENANT_NAME, $par_template_dir, $environment, $baseConfigFile, $buildnumber) = @_;
#	
#	my $YEAR = `date +%Y`;
#	chomp $YEAR;
#	my $tmpl = HTML::Template->new( filename => $par_template_dir.'/notify_template.tmpl' );
#	$tmpl->param(
#   					year     	=> $YEAR,
#   					buildnumber => $buildnumber
#				);
#	#Email::sendMail(uc($environment)." deployment initiated on AP Productization",$tmpl->output, $baseConfigFile, $logger);
#	Email::sendMail("Deployment of ".$TENANT_NAME." to ".uc($environment)." initiated.",$tmpl->output, $baseConfigFile, $logger);
#}

sub sendMail
{
	
    my ($mail_subject, $mail_body , $baseConfigFile, $logger, $deploy_failure) = @_;
    
    #$mail_subject ="ⓓⓔⓥⓞⓟⓢ → ". $mail_subject;
    $mail_subject = Encode::decode('utf-8',"ⓓⓔⓥⓞⓟⓢ →").' '.$mail_subject;
    
    #$mail_subject = '=?utf-8?Q?'.MIME::Base64::decode("ⓓ").'?='.$mail_subject;
    
    #Read property files
	open my $inputData, '<:utf8', $baseConfigFile or ($logger->error("Cannot open configuration file $baseConfigFile : No such file or directory.") and exit 1);
	my $baseConfProperties = new Config::Properties();
	$baseConfProperties->load($inputData);

    my $SMTP_HOST = $baseConfProperties->getProperty('smtp.hostname');
    my $SMTP_PORT = $baseConfProperties->getProperty('smtp.port');
    my $SMTP_USERNAME = $baseConfProperties->getProperty('smtp.username');
    my $SMTP_PASSWORD = Decrypt::getPassword($baseConfProperties->getProperty('smtp.password'));
    my $mail_to_list = $baseConfProperties->getProperty('smpt.receivers');
    #$mail_to_list = 'egov-systems@egovernments.org';   
    my @mail_to = split (',',$mail_to_list);
    my $mail_from = "noreply\@egovernments.org";
    
    my $smtp;
    my $boundary = "eGOV-DEPLOYMENT";
    
	if (not $smtp = Net::SMTP::SSL->new($SMTP_HOST, Port => $SMTP_PORT )) {
	   $logger->error( "Could not connect to smtp server.");
	}
		
	$smtp->auth($SMTP_USERNAME, $SMTP_PASSWORD) || die "Authentication failed!\n";
	
	$smtp->mail($mail_from . "\n");
	$smtp->recipient(@mail_to, { SkipBad => 1 });
	
	$smtp->data();
	$smtp->datasend("From: DevOps Support <" . $mail_from . ">\n");
	$smtp->datasend("To:" . $mail_to_list . "\n");
	$smtp->datasend("Cc:devops-support\@egovernments.org\n");
	$smtp->datasend("Importance: high\n");
	$smtp->datasend("Subject: " . $mail_subject . " \n");
	$smtp->datasend("MIME-Version: 1.0\n");
	$smtp->datasend("Content-type: multipart/mixed;\n\tboundary=\"$boundary\"\n");
	$smtp->datasend("\n");
	$smtp->datasend("\n--$boundary\n");
	$smtp->datasend("Content-type: text/html;charset=\"UTF-8\" \n");
	#$smtp->datasend("Content-Disposition: quoted-printable\n");
	$smtp->datasend("\n");
	$smtp->datasend($mail_body . "\n");
	$smtp->datasend("\n");
	$smtp->datasend("\n--$boundary\n");
	
	if ( $deploy_failure ne "" )
	{
		$smtp->datasend("Content-Disposition: attachment; filename=\"$deploy_failure\"\n");
		$smtp->datasend("Content-Type: application/text; name=\"$deploy_failure\"\n");
		$smtp->datasend("\n");
		open CSVFH, "< $deploy_failure";
		while (<CSVFH>) { chomp; $smtp->datasend("$_\n"); }
		close CSVFH;
		$smtp->datasend("\n");
		$smtp->datasend("--$boundary\n");
	}
	$smtp->dataend();
	$smtp->quit;
}
1;