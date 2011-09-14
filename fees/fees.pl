#!/usr/bin/perl

# Copyright 2007 Liblime ltd
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

## 2011 Filoquin BPBR

use strict;
#use warnings; FIXME - Bug 2505
use CGI;
use Text::CSV;
use C4::Reports::Guided;
use C4::Auth;
use C4::Output;
use C4::Members;
use C4::Dates;
use C4::Debug;
use C4::Branch; # XXX subfield_is_koha_internal_p
use C4::Accounts;


=head1 NAME

fees.pl

=head1 DESCRIPTION

Script para generar y cobrar recibos por cobrador

=over2

=cut

my $input = new CGI;
my $cobrador = $input->param('cobrador');
my $action = $input->param('action');

my $version="0.1.3";
my $db_version="0.1.9";
my $flagsrequired;
my @log =();

$flagsrequired = 'execute_report';
my $dbh=C4::Context->dbh;

my $borrower_attribute_collector='cobrador';
my $ModuloRecibosActivado = C4::Context->preference('ModuloRecibosActivado');
my $ModuloRecibosHeader = C4::Context->preference('ModuloRecibosHeader');
my $ModuloRecibosFooter = C4::Context->preference('ModuloRecibosFooter');
my $ModuloRecibosNumero = C4::Context->preference('ModuloRecibosNumero');
my $ModuloRecibosValorReinscripcion = C4::Context->preference('ModuloRecibosValorReinscripcion');

my $ModuloRecibosVersion = C4::Context->preference('ModuloRecibosVersion');
 if ($ModuloRecibosVersion ne $db_version){
	##
	#si el modulo no es igual a la ultima versión 
	#obligo a vover a la configuración
	##
	$ModuloRecibosActivado =0;	 
 }
  
=Creo el template
=cut
my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "fees/fees.tmpl",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { reports => $flagsrequired },
        debug           => 1,
    }
);

####################
# 
# Inicia la funcionalidad
#
####################

####################
# 
# El modulo no esta activado
# o elegi la accion configurar
# 
####################

if ( (!$ModuloRecibosActivado and $action ne 'Guardar Preferencias') or $action eq 'configurar modulo' ){
	#el modulo recibos no esta activado
	my $sth  = $dbh->do("SELECT c.categorycode , c.description, `fee_amount` , fees_by_year
			FROM categories c
			LEFT JOIN categories_fees cf ON (c.categorycode = cf.categorycode)");

    #my $row = $sth->fetchall_arrayref();
	
	#my @categories_fees=();
	#foreach (@$row){
		
					
	#}
	
	$template->param( 'config' => 1 ,
	'footer' => $ModuloRecibosFooter,
	'ModuloRecibosValorReinscripcion' => $ModuloRecibosValorReinscripcion,
	'header' => $ModuloRecibosHeader,
	'numero' => $ModuloRecibosNumero,
	'version' => $version
	);
}
####################
# 
# El modulo no esta activado
#  o elegi la accion configurar y realize submit del formulario
# 
####################

elsif ($action eq 'Guardar Preferencias'){
	
	# si el modulo no fue activado intento crear la tabla acountline_fees
	if (!$ModuloRecibosActivado) {
			create_acountline_fees_table();
	}
	
	my $header = $input->param('header');
	my $footer = $input->param('footer');
	my $numero = $input->param('numero');
	my $ModuloRecibosValorReinscripcion = $input->param('ModuloRecibosValorReinscripcion');

	#guardo las preferencias en el sistema
	C4::Context->set_preference( 'ModuloRecibosActivado', 1 );
	C4::Context->set_preference( 'ModuloRecibosHeader', $header );
	C4::Context->set_preference( 'ModuloRecibosFooter', $footer );
	C4::Context->set_preference( 'ModuloRecibosNumero', $numero );
	C4::Context->set_preference( 'ModuloRecibosVersion', $db_version );
	C4::Context->set_preference( 'ModuloRecibosValorReinscripcion', $ModuloRecibosValorReinscripcion );
	


	#instalo los reportes de sql
	install_reports();

	# limpio el cache de preferencias
	# es posible que no sea necesario
	C4::Context->clear_syspref_cache();
	# redirijo a la home del modulo
	print $input->redirect("/cgi-bin/koha/fees/fees.pl");

}

####################
# 
# FORMULARIO INICIAL
# El modulo esta activado
# y no elegi ningun cobrador
# 
####################

elsif ( $ModuloRecibosActivado and $action eq '' ) {
    # muestra el selector de cobradores
    $template->param( 'start' => 1 );
    
	# obtengo los cobradores
	my $user = $input->remote_user;
	
    my $sth = $dbh->prepare(
		"SELECT attribute FROM borrower_attributes WHERE CODE='cobrador' GROUP BY attribute"
      );
     $sth->execute();
	my @cobradores = ();

    my $row = $sth->fetchall_arrayref({});

	foreach (@$row){
	  push @cobradores , {cobrador => $_->{attribute}};
	}

	#obtengo las cuotas que aun estan impagas
    my $sth = $dbh->prepare("SELECT year, fees
			FROM accountlines a
			JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
			WHERE a.accounttype = 'fee' AND amountoutstanding > 0 
			GROUP BY year, fees ORDER BY year DESC, fees DESC LIMIT 12");
     $sth->execute();

	my @actives_fees = ();
    my $fee = $sth->fetchall_arrayref({});

	foreach (@$fee){
	  push @actives_fees , {'year' => $_->{year} , 'fees' => $_->{fees}};
	}
	
	#envio la lista de cobradores al tmpl
	$template->param('cobradores' => \@cobradores,'actives_fees' => \@actives_fees  , 'version' => $version );   
}
####################
# 
# FORMULARIO DE COBRADORES
# iniciar Operaciones de cobradores
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'collectors' ) {
	my @collectors=get_collector();
	$template->param('collectors' => \@collectors , 'collectors_page' => 1);
	   

}
####################
# 
# FORMULARIO DE GENERACIÓN  DE CUOTAS
# Genero y elimino cuotas impagas
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'form generar cuotas' ) {
	
	#obtengo las cuotas que aun estan impagas
    my $sth = $dbh->prepare("SELECT year, fees
			FROM accountlines a
			JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
			WHERE a.accounttype = 'fee' AND amountoutstanding > 0 
			GROUP BY year, fees ORDER BY year DESC, fees DESC LIMIT 12");
     $sth->execute();

	my @actives_fees = ();
    my $fee = $sth->fetchall_arrayref({});

	foreach (@$fee){
	  push @actives_fees , {'year' => $_->{year} , 'fees' => $_->{fees}};
	}
	
	#envio la lista de cobradores al tmpl
	
	$template->param('actives_fees' => \@actives_fees , 'generar_cuotas_page' => 1);
	   

}
####################
# 
# FORMULARIO DE OTROS
# Genero form de acciones miselaneas
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'otros' ) {
	my @collectors=get_collector();
	$template->param('collectors' => \@collectors , 'otros' => 1);
	   

}
####################
# 
# REINSCRIBIR A UN SOCIO
#
# Actualizo la información del socio y doy de baja sus deudas y genero nuevas
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'Reinscribir a un socio' ) {
	my $accept = $input->param('accept');
	my $borrowernumber=get_borrowernumber($input->param('borrower'));
	
	if ($accept != 1){
		$template->param (borrowers_bar($borrowernumber));
			
		my $sth = $dbh->prepare("SELECT * FROM accountlines WHERE borrowernumber=? AND amountoutstanding > 0");
		my $accountlines_info = $sth->execute($borrowernumber); 
		my $row = $sth->fetchall_arrayref({});
		my @accountlines =();


		foreach (@$row){
			  push @accountlines , {accountno => $_->{accountno},
									amount => $_->{amountoutstanding},
									description => $_->{description}};

		}
			
		$template->param ('reinscripcion' => 1 , 
						  'accountlines' => \@accountlines,
						  'borrower' => $input->param('borrower')
						  );
	}
	else {
		my $sth = $dbh->prepare("UPDATE accountlines
			SET amountoutstanding=0 , 
			description = CONCAT(description, ' - Deuda dada de baja por reinscripcion')
			WHERE borrowernumber=? AND amountoutstanding > 0");
			
		$sth->execute($borrowernumber); 
		my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
		
		my $year = 1900 + $yearOffset;
		push @log , {'text',"Reinscripcion y Couta societaria ". $month ."-". $year . " -  $borrowernumber $ModuloRecibosValorReinscripcion"};
#		 create_fees(description ,borrowernumber, amount,fees,year,collector,receipt_number)
		create_fees("Reinscripcion y Couta societaria ". $month ."-". $year  ,
			$borrowernumber,$ModuloRecibosValorReinscripcion ,$month,$year,'','');
			
			

	}
}
####################
# 
# CORREGIR CUOTAS A SOCIO
#
# Listo todas las deudas de accountlines y accountlines_fees en un form
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'Corregir a un socio' ) {
	
	my $borrower = $input->param('borrower');


	my $sth = $dbh->prepare("SELECT borrowernumber ,
	firstname ,surname,cardnumber FROM borrowers WHERE cardnumber=? or LOWER(surname) LIKE LOWER(?) ");
	
    my $borrower_info = $sth->execute($borrower , "%$borrower%");    
	my ($borrowernumber ,$firstname ,$surname,$cardnumber ) = $sth->fetchrow_array();

	my $data=GetMember('borrowernumber' => $borrowernumber);
    $template->param( 'recalcular' => 1 );

	

}

####################
# 
# COBRAR CUOTAS A SOCIO
#
# Listo todas las deudas de accountlines y accountlines_fees en un form
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'Cobrar a un socio' ) {
	my $borrowernumber = int($input->param('borrowernumber')) ;
	my $borrower = $input->param('borrower');
	my $firstname;
	my $surname;
	my $cardnumber ;


	if ($borrower ){

		my $sth = $dbh->prepare("SELECT borrowernumber ,
		firstname ,surname,cardnumber FROM borrowers WHERE cardnumber=? or LOWER(surname) LIKE LOWER(?) ");
		my $borrower_info = $sth->execute($borrower , "%$borrower%");    
		 ($borrowernumber ,$firstname ,$surname,$cardnumber ) = $sth->fetchrow_array();
	}	
	
	my $data=GetMember('borrowernumber' => $borrowernumber);
	my $MemberDetails = GetMemberDetails

	my @cobradores = get_collector();
	$template->param ('cobradores_lolo' => \@cobradores);

	if ($borrowernumber){
		my $next_fee = get_next_fee($borrowernumber);
		my $next_fee_text=$next_fee->{'new_period'} ."/" . $next_fee->{'new_year'};
		my $collector= get_collector_by_borrowernumber($borrowernumber);
		
		my @borrowers = ();
		my @accountlines = ();
		my $sth = $dbh->prepare("SELECT a.accountno, FORMAT(a.amountoutstanding,2) as amountoutstanding , a.description
				FROM accountlines a
				JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
				WHERE a.accounttype = 'fee' AND amountoutstanding > 0 
				AND a.borrowernumber=?");
		my $borrower_accountlines = $sth->execute($borrowernumber);
		my $row = $sth->fetchall_arrayref({});
		my $total_amountoutstanding = 0 ;


		 
		foreach (@$row){
  		  $total_amountoutstanding = $total_amountoutstanding + $_->{amountoutstanding};
		  push @accountlines , {accountno => $_->{accountno},
								amount => $_->{amountoutstanding},
								description => $_->{description}};

		}
		


		push @borrowers, {'borrowernumber' => $borrowernumber,
						'firstname' => $data->{'firstname'},
						'surname' => $data->{'surname'},
						 'cardnumber' => $data->{'cardnumber'},
						 'total_amountoutstanding' => $total_amountoutstanding,
						 'accountlines' =>\@accountlines  ,
						 'next_fee_text' => $next_fee_text 
						  };
						 

		$template->param ('title' => "Cobrar cuotas a ". $data->{'firstname'} ." " . $data->{'surname'},
						'cobrar' => 1 , 
						 'collector_selector' => 1 , 
						  'collector' => $collector ,
						'borrowers' =>  \@borrowers ,
						'borrowernumber'  => $borrowernumber,
						
						);
						
		$template->param(
			finesview           => 1,
			firstname           => $data->{'firstname'},
			surname             => $data->{'surname'},
			borrowernumber      => $borrowernumber,
			cardnumber          => $data->{'cardnumber'},
			categorycode        => $data->{'categorycode'},
			category_type       => $data->{'category_type'},
			categoryname		 => $data->{'description'},
			address             => $data->{'address'},
			address2            => $data->{'address2'},
			city                => $data->{'city'},
			zipcode             => $data->{'zipcode'},
			country             => $data->{'country'},
			phone               => $data->{'phone'},
			email               => $data->{'email'},
			branchcode          => $data->{'branchcode'},
			branchname			=> GetBranchName($data->{'branchcode'}),
			is_child            => ($data->{'category_type'} eq 'C'),
	   );

		# cantidad de items scalar(keys %$row)
		
	}
}
####################
# 
# AGREGAR CUOTAS A SOCIO
#
# Genero la proxima cuota y la reenvio
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'new_fee' ) {
	
	my $borrower = int($input->param('borrower'));
	new_fee($borrower);

	
}

####################
# 
# QUITAR CUOTAS A SOCIO
#
# Elimino la entrada de acountlines y acountlines_fees a un socio
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'delete_fee' ) {
	
	my $borrowernumber = int($input->param('borrowernumber'));
	my $accountno = int($input->param('accountno'));
	
	#to-to deberia borrar solo los fees
	my $sth = $dbh->prepare("DELETE FROM accountlines  WHERE borrowernumber=? AND accountno=?");
	$sth->execute($borrowernumber,$accountno );  
	
	my $sth = $dbh->prepare("DELETE FROM accountlines_fees  WHERE borrowernumber=? AND accountno=?");
	$sth->execute($borrowernumber,$accountno );  
	#print $input->redirect("/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber");
	print $input->redirect("/cgi-bin/koha/fees/fees.pl?action=Cobrar+a+un+socio&borrowernumber=$borrowernumber");
	
}

####################
# 
# COBRAR CUOTAS A COBRADOR
#
# Listo todas las deudas de accountlines y accountlines_fees en un form
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'Cargar cuotas a cobrador' ) {
	
	my $collector = $input->param('collector');

	my $sth = $dbh->prepare("SELECT b.borrowernumber ,firstname ,surname,cardnumber 
				FROM borrowers b
				JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = 'cobrador' ) 
				WHERE attribute = ?");
    my $borrower_info = $sth->execute($collector);    
    my $row = $sth->fetchall_arrayref({});
    
    my @borrowers = ();
    
	foreach (@$row){

		my @accountlines = ();
		my $sth = $dbh->prepare("SELECT a.accountno, FORMAT(a.amountoutstanding,2) as amountoutstanding , a.description
				FROM accountlines a
				JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
				WHERE a.accounttype = 'fee' AND amountoutstanding > 0 
				AND a.borrowernumber=?");
		my $borrower_accountlines = $sth->execute($_->{borrowernumber});
		my $row = $sth->fetchall_arrayref({});
		my $total_amountoutstanding = 0 ;
		foreach (@$row){
		  $total_amountoutstanding = $total_amountoutstanding + $_->{amountoutstanding};
		  push @accountlines , {accountno => $_->{accountno},
								amount => $_->{amountoutstanding},
								description => $_->{description}};
		}
		
		if (scalar(@accountlines)){
		  push @borrowers, {'borrowernumber' => $_->{borrowernumber},
						'firstname' => $_->{firstname} ,
						'surname' => $_->{surname},
						 'cardnumber' => $_->{cardnumber},
						 'total_amountoutstanding' => $total_amountoutstanding,
						 'accountlines' =>\@accountlines
						 };
		}
	}
		$template->param ('title' => "Cobrar cuotas de $collector :",
						'cobrar' => 1 , 
						'borrowers' =>  \@borrowers
						);

		# cantidad de items scalar(keys %$row)
		
	
}

####################
# 
# RECIBOS PARA UN COBRADOR
#
# Listo todas las deudas de accountlines y accountlines_fees en forma de recibos
# 
####################

elsif ( $ModuloRecibosActivado and $action eq 'Recibos por cobrador' ) {
	my $iter = 0;
	my $pag = 1;

	my $collector = $input->param('collector');
	my $saltodepagina  = int($input->param('saltodepagina'));
	my $tagEntreRecibos ="";


	my $sth = $dbh->prepare("SELECT b.borrowernumber ,firstname ,surname,cardnumber ,address,city
				FROM borrowers b
				JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = 'cobrador' ) 
				WHERE attribute = ?");
    my $borrower_info = $sth->execute($collector);    
    my $row = $sth->fetchall_arrayref({});

    my @borrowers = ();
    
	foreach (@$row){
		my @accountlines = ();
		my $sth = $dbh->prepare("SELECT a.accountno, FORMAT(a.amountoutstanding,2) as amountoutstanding , a.description
				FROM accountlines a
				JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
				WHERE a.accounttype = 'fee' AND amountoutstanding > 0 
				AND a.borrowernumber=?");
		my $borrower_accountlines = $sth->execute($_->{borrowernumber});
		my $row = $sth->fetchall_arrayref({});
		my $total_amountoutstanding = 0 ;
		foreach (@$row){
		  $total_amountoutstanding = $total_amountoutstanding + $_->{amountoutstanding};
		  push @accountlines , {accountno => $_->{accountno},
								amount => $_->{amountoutstanding},
								description => $_->{description}};
		}

		
		if (scalar(@accountlines)){
  		  $iter ++;
			if($iter >= $saltodepagina ){
				 $iter=0;
				 $tagEntreRecibos ="</table>Pagina $pag<hr style=\"PAGE-BREAK-AFTER: always;\"> <table><tr><th>Original</th><th>Duplicado</th></tr>";
				 $pag++;
			} 
			else {
				$tagEntreRecibos ="";
			}
  		  $ModuloRecibosNumero ++;

		  push @borrowers, {'borrowernumber' => $_->{borrowernumber},
						'tagEntreRecibos' => $tagEntreRecibos,
						'firstname' => $_->{firstname} ,
						'surname' => $_->{surname},
						 'cardnumber' => $_->{cardnumber},
						  'address' => $_->{address},
						  'city' => $_->{city},
						 'total_amountoutstanding' => $total_amountoutstanding,
						 'accountlines' =>\@accountlines ,
						 'collector' => $collector,
						 'number' => $ModuloRecibosNumero,
						 'head' => $ModuloRecibosHeader,
						'footer' =>  $ModuloRecibosFooter ,
						'total_amountoutstanding' => $total_amountoutstanding
						 };
		}
	}
		$template->param ('title' => "Cobrar cuotas de $collector :",
						'recibos' => 1 , 
						'borrowers' =>  \@borrowers
						);

		# cantidad de items scalar(keys %$row)
		C4::Context->set_preference( 'ModuloRecibosNumero', $ModuloRecibosNumero );
	
	
}

####################
# 
# GUARDAR CUOTAS COBRADAS
#
# Inserto las entradas de acount lines
# 
####################
 elsif ($ModuloRecibosActivado and $action eq 'guardar cobro' ) {
    

	my $user = $input->remote_user;
	my $collector = $input->param('collector');
	$template->param('guardar' => 1);
	my @accountlines = ();
	my @borrowers = ();
	my $total_amountoutstanding = 0 ;
	my $borrowernumber = 0;
	my $lastborrowernumber = 0;
	my $more='';
	
	my @param_names = $input->param();
	foreach (@param_names) {
		if (rindex($_,'monto') == 0){
			my $monto = $input->param($_);
			if($monto > 0){

				my @post_data = split("\_",$_);
				my $borrowernumber = int(@post_data[1]);
				my $accountno =int(@post_data[2]); 	
				my ($description,$accounttype,$amount , $amountoutstanding , $year , $fees,$receipt_number) = get_fee_data($borrowernumber,$accountno);

				if ($accounttype =="fee" and $amountoutstanding > 0){
					if ($collector){
						$more="($collector)";
					}
					$total_amountoutstanding =$total_amountoutstanding + $amountoutstanding ;
					 push @accountlines , {accountno => $accountno,
							amount => $amountoutstanding,
							description => $description};
					$lastborrowernumber= $borrowernumber;
	
					pay_fees("Cobrado $description $more" ,$borrowernumber,$accountno, $monto,$fees,$year,$collector,$receipt_number);
				}
				
				
			##	push @log , {'text',$_};
			##	push @log , {'text',$accounttype};
			if ($collector){

				$template->param('show_borrow_bar' => 1);

				push @log , {'text',"Monto pagado $monto"};
			}
			
			}
		}
	}
	
				# to-do deberia crear recibos si el cobrador es nulo
				if(!$collector){
					
						my $sth = $dbh->prepare("SELECT borrowernumber ,firstname ,surname,cardnumber ,
								city , categorycode ,  address , address2 , city , zipcode,
								country, phone, email , branchcode
						FROM borrowers 
						WHERE borrowernumber = ?");

												
						my $borrower_info = $sth->execute($lastborrowernumber);    
						my $data = $sth->fetchrow_hashref();
						
						push @borrowers, {'borrowernumber' => $data->{'borrowernumber'},
						'firstname' => $data->{'firstname'} ,
						'surname' => $data->{'surname'},
						 'cardnumber' => $data->{'cardnumber'},
						  'address' => $data->{'address'},
						  'city' => $data->{'city'},
						 'total_amountoutstanding' => $total_amountoutstanding,
						 'accountlines' =>\@accountlines ,
						 'collector' => '',
						 'number' => $ModuloRecibosNumero,
						 'head' => $ModuloRecibosHeader,
						'footer' =>  $ModuloRecibosFooter ,
						'total_amountoutstanding' => $total_amountoutstanding
						 };
					$template->param('recibos' => 1, 'borrowers' =>  \@borrowers);
					
					$template->param(
						finesview           => 1,
						firstname           => $data->{'firstname'},
						surname             => $data->{'surname'},
						borrowernumber      => $lastborrowernumber,
						cardnumber          => $data->{'cardnumber'},
						categorycode        => $data->{'categorycode'},
						category_type       => $data->{'category_type'},
						categoryname		 => $data->{'description'},
						address             => $data->{'address'},
						address2            => $data->{'address2'},
						city                => $data->{'city'},
						zipcode             => $data->{'zipcode'},
						country             => $data->{'country'},
						phone               => $data->{'phone'},
						email               => $data->{'email'},
						branchcode          => $data->{'branchcode'},
						branchname			=> GetBranchName($data->{'branchcode'}),
						is_child            => ($data->{'category_type'} eq 'C'),
				   );

				}	 
			##if ($collector){
			##	print $input->redirect("/cgi-bin/koha/fees/fees.pl");
			
			##}
	
}

####################
# 
# IMPRIMIR UN RECIBO 
#
# Genero un recibo para una entrada
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'Imprimir recibo' ) {



				   

}

####################
# 
# GENERAR CUOTAS PARA UN PERIODO
#
# Genero las entradas en acountlines y accountlines_fees
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'Generar cuotas' ) {

	my $year = int($input->param('year'));
	my $period = int($input->param('period'));

	#obtener borrowers que no tienen generada esta cuota
	my $sth = $dbh->prepare("SELECT b.borrowernumber ,enrolmentfee
			FROM borrowers b /* socios */
			JOIN borrower_attributes ba ON (ba.borrowernumber=b.borrowernumber AND CODE='ult_pago') 
			LEFT JOIN accountlines_fees f ON (b.borrowernumber=f.borrowernumber AND year=? AND fees=?) /*cuotas del socio*/
			JOIN categories cat ON (cat.categorycode = b.categorycode AND cat.enrolmentfee > 0)  /* categoria del socio*/
			WHERE f.borrowernumber IS NULL AND dateenrolled <= DATE(CONCAT_WS('-',?,?,'01'))
			AND dateexpiry > NOW()
			AND STR_TO_DATE(attribute,'%m-%Y') < DATE(CONCAT_WS('-',?,?,'00'))");
	
    my $borrowers = $sth->execute($year, $period,$year, $period,$year, $period);
    my $row = $sth->fetchall_arrayref({});
	my $iter=0;
	foreach (@$row){
		create_fees("Couta societaria $period-$year" ,$_->{borrowernumber}, $_->{enrolmentfee},$period,$year,'','');
		$iter++;
	}
	push (@log ,{text => "$iter Cuotas generadas" });

}

####################
# 
# ELMINAR CUOTAS PARA UN PERIODO
#
# Elimino las entradas en acountlines y accountlines_fees que cumple con la condicion y no estan pagas
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'Eliminar cuotas' ) {
	
	my @fees_data= split("\_",$input->param('fees'));
	my $fee=int(@fees_data[0]);
	my $year=int(@fees_data[1]);
	my $sth = $dbh->prepare("DELETE accountlines,accountlines_fees FROM accountlines 
		LEFT JOIN accountlines_fees ON (accountlines.borrowernumber=accountlines_fees.borrowernumber 
				AND accountlines.accountno=accountlines_fees.accountno)
		WHERE accountlines.accounttype = 'fee' AND amountoutstanding > 0 AND year=? AND fees=?");

    my $borrowers = $sth->execute($year, $fee);
    
   	push (@log ,{text => "eliminadas las cuotas de $fee - $year" });
 

	
}

####################
# 
# RENOMBRAR A UN COBRADOR
#
# Cambio el nombre de el cobrador
# 
####################
elsif ( $ModuloRecibosActivado and $action eq 'renombrar cobrador' ) {
	
	my $collector=$input->param('collector');
	my $newName=$input->param('newName');


	my $sth = $dbh->prepare('UPDATE borrower_attributes 
		SET attribute=?
		WHERE CODE="cobrador" AND attribute=?');
	$sth->execute($newName, $collector);
	
	my $sth = $dbh->prepare('UPDATE authorised_values
	SET authorised_value=? , lib = ?
	WHERE category="Cobrador" AND authorised_value=?');
	
	$sth->execute($newName, $newName, $collector);
	
   	push (@log ,{text => "Renombrado  $collector como  $newName" });
 

	
}

=El modulo esta activado
  y genero la lista de usuarios que deben pagar cuotas
  los items son uno por cuota y solo para cuotas accounttype ="A"
=cut
 elsif ($ModuloRecibosActivado and $action eq 'Cobrar' and $cobrador ne '' ) {
	$template->param('cobrar' => 1);

	#obtengo los items tipo "A" sin pagar 
	#(ojo) que si realize un credito aun aparecen 
	#un subquery deberia restringir a los socios que tienen deuda

	my $sth = $dbh->prepare('SELECT b.borrowernumber , al.accountno , al.description , surname ,firstname ,b.cardnumber ,
				FORMAT(al.amount,2) AS amount ,ba.attribute  AS cobrador , 
				FORMAT(cat.enrolmentfee,2) AS montocuota , b.address ,b.city
				FROM borrowers b /* socios */
				JOIN accountlines al ON (b.borrowernumber=al.borrowernumber  ) /* entradas en el libro diario */
				JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = "cobrador" ) /* atributo cobrador */JOIN categories cat ON (cat.categorycode = b.categorycode)  /* categoria del socio*/
				WHERE ba.attribute = ?  /* donde cobrador es x */
				AND accounttype ="A"
				AND amountoutstanding > 0 /*lo que resta de la cuota*/ ');

    $sth->execute($cobrador);
	my @rows = ();
    my $row = $sth->fetchall_arrayref({});

	my $iter =0;
	
	#loopeo para generar un array con datos
	foreach (@$row){
		$iter++;
        push @rows , {borrowernumber => $_->{borrowernumber},
			surname => $_->{surname},
			firstname => $_->{firstname},
			cardnumber => $_->{cardnumber},
			accountno => $_->{accountno},
			description => $_->{description}, 
			amount => $_->{amount},
			number => $_->{number},
			address => $_->{address},
			city => $_->{city},
			montocuota => $_->{montocuota},						
			cobrador => $_->{cobrador}};

    }
    
    #envio los datos al tmpl
    $template->param('results' => \@rows);


}

=El modulo esta activado
  y genero la deuda acumulada a la migracion
=cut
 elsif ($ModuloRecibosActivado and $action eq 'Generar deuda'  ) {

	$template->param('guardar' => 1);

 	my $sth = $dbh->prepare( 'SELECT b.borrowernumber,
					PERIOD_DIFF(DATE_FORMAT(NOW(),"%Y%m"),
						DATE_FORMAT(STR_TO_DATE(CONCAT("1-",attribute),"%d-%m-%Y"),"%Y%m")) deuda, enrolmentfee 
						, MONTH(NOW()) AS mes, YEAR(NOW()) AS anio 
					FROM borrower_attributes  ba
					JOIN borrowers b ON (b.borrowernumber=ba.borrowernumber)
					JOIN categories cat ON (cat.categorycode = b.categorycode AND cat.categorycode ="AD" )  /* categoria del socio*/
					WHERE CODE="ult_pago" 
					AND PERIOD_DIFF(DATE_FORMAT(NOW(),"%Y%m"),
						DATE_FORMAT(STR_TO_DATE(CONCAT("1-",attribute),"%d-%m-%Y"),"%Y%m"))  <20
					/*AND 
					PERIOD_DIFF(DATE_FORMAT(NOW(),"%Y%m"),
						DATE_FORMAT(STR_TO_DATE(CONCAT("1-",attribute),"%d-%m-%Y"),"%Y%m"))  > 0*/');
    $sth->execute();
    
    my $row = $sth->fetchall_arrayref({});
	
	my @output=();
	push @output ,{ text => "Iniciando generacion"};
	
	foreach (@$row){
		my $borrowernumber = $_->{borrowernumber};
		my $meses = int($_->{deuda});
		my $fees = $_->{mes};
		my $year = $_->{anio};
		my $enrolmentfee = $_->{enrolmentfee};
		push (@log ,{text => "$borrowernumber : $meses" });
		if ($meses > 0){
			

			while ($meses>0){
				my $nextaccntno = getnextacctno($borrowernumber);			
				my $mes_cuota = $meses - 1;
				$dbh->do("INSERT INTO accountlines
					(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
					VALUES
					($borrowernumber, $nextaccntno,  NOW(), $enrolmentfee, 
					 CONCAT('Deuda Migrada ', MONTH(NOW() - INTERVAL $mes_cuota MONTH),'-',YEAR(NOW() - INTERVAL $mes_cuota MONTH)) ,  'fee', $enrolmentfee, 1, 0)");

				$dbh->do("INSERT INTO accountlines_fees (borrowernumber, accountno, year, fees, collector, receipt_number)
				VALUES ($borrowernumber, $nextaccntno, YEAR(NOW() - INTERVAL $mes_cuota MONTH),  MONTH(NOW() - INTERVAL $mes_cuota MONTH), 
						'', '')");
					

					
					$meses=$meses-1;	
				}
		} else {
			
			while ($meses<0){
				my $nextaccntno = getnextacctno($borrowernumber);			
				my $mes_cuota = $meses + 1;

				$dbh->do("INSERT INTO accountlines
					(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
					VALUES
					($borrowernumber, $nextaccntno,  NOW(), $enrolmentfee, 
					 CONCAT('Couta Migrada ', MONTH(NOW() - INTERVAL $mes_cuota MONTH),'-',YEAR(NOW() - INTERVAL $mes_cuota MONTH)) ,  
					 'fee', 0, 1, 0)");

				$dbh->do("INSERT INTO accountlines_fees (borrowernumber, accountno, year, fees, collector, receipt_number)
				VALUES ($borrowernumber, $nextaccntno, YEAR(NOW() - INTERVAL $mes_cuota MONTH),  MONTH(NOW() - INTERVAL $mes_cuota MONTH), 
						'', '')");
				my $nextaccntno = getnextacctno($borrowernumber);			
				$dbh->do("INSERT INTO accountlines
				(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
				VALUES
				($borrowernumber, $nextaccntno,  NOW(), 0 - '$enrolmentfee', 
				 CONCAT('Pago Migrado ', MONTH(NOW() - INTERVAL $mes_cuota MONTH),'-',YEAR(NOW() - INTERVAL $mes_cuota MONTH)) 
				,  'Pay', 0, 1, 0)");

				$dbh->do("INSERT INTO accountlines_fees (borrowernumber, accountno, year, fees, collector, receipt_number)
				VALUES ($borrowernumber, $nextaccntno, YEAR(NOW() - INTERVAL $mes_cuota MONTH),  MONTH(NOW() - INTERVAL $mes_cuota MONTH), 
						'', '')");


					push (@log ,{text => $meses });


				$meses++;
			}
			
		}

	} 



}
=El modulo esta activado
  y importo las cuotas de un csv
=cut
 elsif ($ModuloRecibosActivado and $action eq 'Importar cuotas' ) {
	#Obtengo las lineas a importar
	$template->param('guardar' => 1);

 	my $sth = $dbh->prepare( 'SELECT borrowernumber, ia.*
			FROM import_acountlines ia
			JOIN borrowers b ON (ia.socio = b.cardnumber)');
    $sth->execute();
    
    my $row = $sth->fetchall_arrayref({});
	
	my @output=();
	push @output ,{ text => "Iniciando importacion"};
	
	foreach (@$row){
			
			import_acountlines($_->{borrowernumber}, $_->{fechaPago},$_->{fechaCobro},$_->{cobrador},$_->{monto});
			push @output ,{ text => "Se agrego un pago para el cobrador " . $_->{cobrador} . $_->{borrowernumber} ." fecha " .$_->{fechaPago} ."|".$_->{fechaCobro}};

	}

		$template->param('log' => \@output);


	 
}
=El modulo esta activado
  y genero las coutas para mes y año 
=cut
 elsif ($ModuloRecibosActivado and $action eq 'Generar cuotas' and $cobrador ne '' ) {
	my $anio = int($input->param('anio'));
	my $mes = int($input->param('mes'));
	$template->param('guardar' => 1);

	# obtengo Quienes no tienen creadas las cuotas  ese mes
	my $query ="SELECT b.borrowernumber ,c.enrolmentfee
			FROM borrowers b /* socios */
			LEFT JOIN accountlines al ON (b.borrowernumber=al.borrowernumber 
					AND al.accounttype='A' AND YEAR(al.date)=$anio  AND MONTH(al.date)=$mes ) /* entradas en el libro diario */
			JOIN categories c  ON(c.categorycode =b.categorycode AND c.enrolmentfee > 0) 
			WHERE al.date IS NULL
			AND DATE(CONCAT_WS('-',YEAR(b.dateenrolled), MONTH(b.dateenrolled),'1')) <= DATE(CONCAT_WS('-','$anio', '$mes','1'))";
 	my $sth = $dbh->prepare( $query);

    $sth->execute();
    my $row = $sth->fetchall_arrayref({});
	
	my @output=( );
	push @output ,{ text => "Generando"};
	
	foreach (@$row){
			push @output ,{ text => create_cuota($_->{borrowernumber}, $_->{enrolmentfee},$mes,$anio)};
	}
	push @output ,{ text => "Fin"};

		$template->param('results' => \@output);

}
=El modulo esta activado
  y veo resumen de cobre de un cobrador
=cut
 elsif ($ModuloRecibosActivado and $action eq 'ver resumen' and $cobrador ne '' ) {
	 
	my $report_id=get_report_by_name('Resumen mensual de cobros por cobrador');
	my $anio = $input->param('anio');
	my $mes = $input->param('mes');

	print $input->redirect("/cgi-bin/koha/reports/guided_reports.pl?phase=Run this report&reports=$report_id&sql_params=$cobrador&sql_params=$anio&sql_params=$mes");




}
$template->param('log' => \@log);


foreach (1..6) {
    $template->param('build' . $_) and $template->param(buildx => $_) and last;
}
$template->param(   'referer' => $input->referer(),
                    'DHTMLcalendar_dateformat' => C4::Dates->DHTMLcalendar(),
                );

#genero la salida html
output_html_with_http_headers $input, $cookie, $template->output;

=Funciones utilizadas
  en la instalación
=cut

=create_acountline_fees_table
   creo la tabla para contener la informacion de las coutas
=cut

sub   create_acountline_fees_table{
	my $dbh  = C4::Context->dbh;
	 
	$dbh->do("CREATE TABLE IF NOT EXISTS  `accountlines_fees` (
	  `borrowernumber` INT(11) NOT NULL,
	  `accountno` SMALLINT(6) NOT NULL,
	  `year` YEAR(4) NOT NULL,
	  `fees` INT(3) NOT NULL,
	  `collector` VARCHAR(10) DEFAULT NULL,
	  `receipt_number` INT(5) DEFAULT NULL,
	  PRIMARY KEY  (`borrowernumber`,`accountno`)
	) ENGINE=INNODB DEFAULT CHARSET=utf8");
	
}

#subrutina que inserta reportes para los cobradores
sub install_reports{
	 my $dbh  = C4::Context->dbh;
	 my $user = $input->remote_user;
	 
			
			#to-do los reportes tendrian que estar en un array
			my $reporte1_name ="Resumen de cuenta por cobrador";
			my $reporte1_sql = 'SELECT cardnumber ,  CONCAT_WS(" ",firstname , surname) AS nombre , 
								format(SUM(amountoutstanding),2) as deuda
								FROM  borrowers b
								JOIN borrower_attributes ba ON ( b.borrowernumber =  ba.borrowernumber AND ba.code="cobrador" AND attribute  like <<cobrador>>) 
								left JOIN accountlines a ON (a.borrowernumber=b.borrowernumber ) 
								where categorycode = "NI" or categorycode = "AD"
								GROUP BY b.borrowernumber
								ORDER BY cardnumber + 0 ASC';				
			my $reporte1_notes="Con este informe puede conocer cuanto falta por cobrar a un cobrador. ";
			#busco el reporte por nombre
			my $report_id=get_report_by_name($reporte1_name);

			#Si el reporte existe lo actualizo y sino lo grabo			
			if ($report_id){
				update_sql($report_id,$reporte1_sql,$reporte1_name,$reporte1_notes);
			} else {

				save_report($user, $reporte1_sql,$reporte1_name,1,$reporte1_notes);
			}
=quitado

			my $reporte2_name ="Resumen mensual de cobros por cobrador";
			my $reporte2_sql = "SELECT b.cardnumber AS Carnet , CONCAT_WS(' ', surname ,firstname) AS Nombre  ,
			 (al.amount * -1) AS Monto, ba.attribute  AS Cobrador
			FROM borrowers b /* socios */
			JOIN accountlines al ON (b.borrowernumber=al.borrowernumber  ) /* entradas en el libro diario */
			JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = 'cobrador' ) /* atributo cobrador */JOIN categories cat ON (cat.categorycode = b.categorycode)  /* categoria del socio*/
			WHERE ba.attribute = <<cobrador>> 
			AND al.accounttype='pay' AND al.description = CONCAT('Cobrado por ' ,ba.attribute)
			AND YEAR(al.date) = <<anio>> AND MONTH(al.date)= <<mes>>";

			my $reporte2_notes="Con este informe puede conocer cuanto falta por cobrar. ";
			
			#busco el reporte por nombre
			my $report_id=get_report_by_name($reporte2_name);

			#Si el reporte existe lo actualizo y sino lo gravo			
			if ($report_id){
				update_sql($report_id,$reporte2_sql,$reporte2_name,$reporte2_notes);
			} else {

				save_report($user, $reporte2_sql,$reporte2_name,1,$reporte2_notes);
			}
=cut
			
			
}


=get_report_by_name($reportname)
  Obtiene el id del reporte por nombre
=cut
sub get_report_by_name{
	 my $reportname = shift;
	 my $dbh  = C4::Context->dbh;	
     my $query = " SELECT id FROM saved_sql WHERE report_name = ?";
	 my $sth   = $dbh->prepare($query);
	 $sth->execute($reportname);
	 my $data = $sth->fetchrow_hashref();
	 return $data->{'id'}

}
=receipt(accountlines,accountno)
  Crea un array de recibos
=cut
sub make_receipt{
	my @accountlines = shift;
	my @borrower = shift;
}
=get_borrower_data(borrowernumber)
  Obtiene información sobre un socio
=cut
sub get_borrower_data{
	
	 my $borrowernumber = shift;
	 my $sth = $dbh->prepare("SELECT * FROM  borrowers WHERE borrowernumber = ?");
	 my $borrower_info = $sth->execute($borrowernumber);    
     return $sth->fetchrow_hashref;
	 
}
=get_fee_data(borrowernumber,accountno)
  Obtiene información de una entrada
=cut
sub get_fee_data{
	 my $borrowernumber = shift;
	 my $accountno = shift;
	 my $sth = $dbh->prepare("SELECT description, accounttype,amount , amountoutstanding , year , fees,receipt_number
		FROM accountlines a
		JOIN accountlines_fees f ON (a.borrowernumber=f.borrowernumber AND a.accountno=f.accountno)
		where a.borrowernumber = ? and a.accountno =?");
     my $borrower_info = $sth->execute($borrowernumber,$accountno);    
     return $sth->fetchrow_array;
	
}
=Inserto una cuota  en acountlines
 create_fees(description ,borrowernumber, amount,fees,year,collector,receipt_number)
=cut
sub create_fees{
	my $description = shift;
	my $borrowernumber = shift;
	my $amount = shift | 0;
	my $fees = shift;
	my $year = shift;
	my $collector = shift | '';
    my $receipt_number = shift | 0 ;
    my $nextaccntno = getnextacctno($borrowernumber);
    
	$dbh->do("INSERT INTO accountlines
	(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
	VALUES
	($borrowernumber, $nextaccntno,  concat_ws('-','$year','$fees','1'), $amount, '$description',  'fee', $amount, 1, 0)") or die  $dbh->errstr;

	$dbh->do("INSERT INTO accountlines_fees (borrowernumber, accountno, year, fees, collector, receipt_number)
				VALUES ($borrowernumber, $nextaccntno, $year, $fees, '$collector', $receipt_number)") or die  $dbh->errstr;

	return $nextaccntno;

}

=Inserto una cuota  en acountlines
 pay_fees(description ,borrowernumber,fee_accntno, amount,fees,year,[collector],[receipt_number])
=cut
sub pay_fees{
	my $description = shift;
	my $borrowernumber = int(shift);
    my $fee_accntno = int(shift);
	my $amount = shift ;
	my $fees = int(shift);
	my $year = int(shift);
	my $collector = shift | '';
    my $receipt_number = shift | 0 ;
    my $nextaccntno = getnextacctno($borrowernumber);
    
    if($fee_accntno){
				# Seteo la deuda de la operación en (actual - pagado)
				# esto funciona bien si pago todo o parte de la cuota
				# si pago de más produce extraños resultados
				# habria que hacer una entrada nueva (¿credito? "C") con el resto si
				# el pago es mayor a la deuda
				
				$dbh->do("UPDATE  accountlines
					SET     amountoutstanding = (amountoutstanding - $amount)
					WHERE   borrowernumber = $borrowernumber 
					AND   accountno = $fee_accntno");
		}
    
    #inserto un  entrada de pagos en accountlines y accountlines_fees
    
	$dbh->do("INSERT INTO accountlines
	(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
	VALUES
	($borrowernumber, $nextaccntno,  now(), 0 - '$amount', '$description',  'Pay', 0, 1, 0)");

	$dbh->do("INSERT INTO accountlines_fees (borrowernumber, accountno, year, fees, collector, receipt_number)
				VALUES ($borrowernumber, $nextaccntno, $year, $fees, '$collector', $receipt_number)");

	

}

=Obtengo la proxima cuota a generar
 get_next_fee(borrowernumber)
=cut
sub get_next_fee{
	my $borrowernumber = shift;
 	my $sth = $dbh->prepare('SELECT DATE(CONCAT_WS("-",YEAR, fees,"1")) AS last_fee , 
		YEAR(DATE(CONCAT_WS("-",YEAR, fees,"1")) + INTERVAL 1 MONTH) AS new_year 
		,MONTH(DATE(CONCAT_WS("-",YEAR, fees,"1")) + INTERVAL 1 MONTH) AS new_period
		FROM accountlines_fees 
		WHERE borrowernumber = ?
		ORDER BY last_fee DESC LIMIT 1');

    $sth->execute($borrowernumber);
	my $data = $sth->fetchrow_hashref();
	
	if($data->{'new_period'}=="" or $data->{'new_period'}==0 ){
	 	my $sth = $dbh->prepare("SELECT attribute 
			FROM borrower_attributes 
			WHERE CODE='ult_pago' AND borrowernumber=?");

			$sth->execute($borrowernumber);
			my $new_date = $sth->fetchrow_hashref();
			my @date = split("-",$new_date->{'attribute'});
			$data->{'new_period'} = @date[0];
			$data->{'new_year'} = @date[1];
	}

	return $data;
}
=Inserto una cuota y un pago en acountlines
 new_fee(borrowernumber)
=cut
sub new_fee{
	my $borrowernumber = shift;
	my $borrower = get_borrower_data($borrowernumber);
 	my $sth = $dbh->prepare('SELECT DATE(CONCAT_WS("-",YEAR, fees,"1")) AS last_fee , 
		YEAR(DATE(CONCAT_WS("-",YEAR, fees,"1")) + INTERVAL 1 MONTH) AS new_year 
		,MONTH(DATE(CONCAT_WS("-",YEAR, fees,"1")) + INTERVAL 1 MONTH) AS new_period
		FROM accountlines_fees 
		WHERE borrowernumber = ?
		ORDER BY last_fee DESC LIMIT 1');

    $sth->execute($borrowernumber);
	my $data = $sth->fetchrow_hashref();
	
	if($data->{'new_period'}=="" or $data->{'new_period'}==0 ){
	 	my $sth = $dbh->prepare("SELECT attribute 
			FROM borrower_attributes 
			WHERE CODE='ult_pago' AND borrowernumber=?");

			$sth->execute($borrowernumber);
			my $new_date = $sth->fetchrow_hashref();
			my @date = split("-",$new_date->{'attribute'});
			$data->{'new_period'} = @date[0];
			$data->{'new_year'} = @date[1];
	}

	create_fees("Couta societaria ". $data->{'new_period'} ."-". $data->{'new_year'}  ,$borrowernumber, 
			'10',$data->{'new_period'},$data->{'new_year'},'','');
			
	print $input-> redirect ('/cgi-bin/koha/fees/fees.pl?borrower='. $borrower->{'cardnumber'}  .
		'&action=Cobrar a un socio');


}
=Inserto una cuota y un pago en acountlines
 import_acountlines(borrowernumber, fechaPago,fechaCobro,cobrador,monto)
=cut
sub get_collector {

		my $sth = $dbh->prepare(
			"SELECT attribute FROM borrower_attributes WHERE CODE='cobrador' GROUP BY attribute"
		  );
		$sth->execute();
		my @cobradores = ();

		my $row = $sth->fetchall_arrayref({});

		foreach (@$row){
		  push @cobradores , {cobrador => $_->{attribute}};
		}
		
		return @cobradores;
}		
=Inserto una cuota y un pago en acountlines
 import_acountlines(borrowernumber, fechaPago,fechaCobro,cobrador,monto)
=cut
sub get_collector_by_borrowernumber {
	my $borrowernumber = shift;
	my $sth = $dbh->prepare("SELECT attribute FROM borrower_attributes WHERE  borrowernumber=? AND CODE='cobrador'");
	my $borrower_info = $sth->execute($borrowernumber );    
	my ($borrower) = $sth->fetchrow_hashref();
	return $borrower->{'attribute'};

	
}

=Obtengo el borrower number
	get_borrowernumber($borrower)
=cut
sub get_borrowernumber{
	my $borrower = shift;
	
	my $sth = $dbh->prepare("SELECT borrowernumber 
							FROM borrowers WHERE cardnumber=? or LOWER(surname) LIKE LOWER(?) ");
							
    my $borrower_info = $sth->execute($borrower , "%$borrower%");    
	my ($borrower) = $sth->fetchrow_hashref();
	return $borrower->{'borrowernumber'};
	
}
=Agrego al template la barra de boorowers 
	borrowers_bar($borrowernumber)
=cut
sub borrowers_bar{
	my $borrowernumber = shift ;
	
	my $data=GetMember('borrowernumber' => $borrowernumber);
	my @return =();
	push  @return , {
						finesview           => 1,
						firstname           => $data->{'firstname'},
						surname             => $data->{'surname'},
						borrowernumber      => $borrowernumber	,
						cardnumber          => $data->{'cardnumber'},
						categorycode        => $data->{'categorycode'},
						category_type       => $data->{'category_type'},
						categoryname		 => $data->{'description'},
						address             => $data->{'address'},
						address2            => $data->{'address2'},
						city                => $data->{'city'},
						zipcode             => $data->{'zipcode'},
						country             => $data->{'country'},
						phone               => $data->{'phone'},
						email               => $data->{'email'},
						branchcode          => $data->{'branchcode'},
						branchname			=> GetBranchName($data->{'branchcode'}),
						is_child            => ($data->{'category_type'} eq 'C'),
				   };
	return @return;
				   

}		



=Inserto una cuota y un pago en acountlines
 import_acountlines(borrowernumber, fechaPago,fechaCobro,cobrador,monto)
=cut
sub import_acountlines{
	my $borrowernumber = shift;
	my $fechaPago = shift;
	my $fechaCobro= shift;
	my $cobrador = shift;
	my $monto= shift;
    my $nextaccntno = getnextacctno($borrowernumber);

	$dbh->do("INSERT INTO accountlines
	(borrowernumber, accountno,  date, amount, description,  accounttype, amountoutstanding,  notify_id, notify_level)
	VALUES
	($borrowernumber, $nextaccntno,  '$fechaPago', $monto, 'Couta hasta $fechaCobro',  'A', 0, 1, 0)");
					
				#inserto el registro de pago por el total en negativo
				#y escribo 	Cobrado por $cobrador  en la descripción
				#para poder recuperar la info del quia en un reporte
	my $nextaccntno = getnextacctno($borrowernumber);				
	my $payment = 0 - $monto;
	my $des ="";
	if ( ($cobrador =~ /^-?[\.|\d]*\Z/ ) ) {
		$des= "recibo numero $cobrador";
	}
	else {
		$des= "Cobrado por $cobrador";
	}

	$dbh->do( "INSERT INTO     accountlines
               (borrowernumber, accountno, date, amount,
                description, accounttype, amountoutstanding)
				VALUES( $borrowernumber  , $nextaccntno, '$fechaPago', $payment,
                 '$des', 'Pay', 0)" );
}
=array repostes


 push @reportes , {name => "Estado de cuenta de socios por cobrador" ,
						sql => 'SELECT b.cardnumber , CONCAT_WS(" ", surname ,firstname) AS Nombre ,
							ba.attribute  AS cobrador , 
							FORMAT( SUM(amountoutstanding),2) AS Deuda, ROUND( SUM(amountoutstanding) / cat.enrolmentfee) AS coutas
							FROM borrowers b /* socios */
							JOIN accountlines al ON (b.borrowernumber=al.borrowernumber  ) /* entradas en el libro diario */
							JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = "cobrador" ) /* atributo cobrador */JOIN categories cat ON (cat.categorycode = b.categorycode)  /* categoria del socio*/
							WHERE ba.attribute = <<cobrador>>  /* donde cobrador es lito */
							AND accounttype ="A"
							GROUP BY b.borrowernumber' , 
						notes => 'Con este informe puede conocer cuanto falta por cobrar.'};
	 push @reportes , {name => "Resumen mensual de cobros por cobrador" ,
					  sql => "SELECT b.cardnumber AS Carnet , CONCAT_WS(' ', surname ,firstname) AS Nombre  ,
						 (al.amount * -1) AS Monto, ba.attribute  AS Cobrador
						FROM borrowers b /* socios */
						JOIN accountlines al ON (b.borrowernumber=al.borrowernumber  ) /* entradas en el libro diario */
						JOIN borrower_attributes ba ON (b.borrowernumber=ba .borrowernumber AND ba.code = 'cobrador' ) /* atributo cobrador */JOIN categories cat ON (cat.categorycode = b.categorycode)  /* categoria del socio*/
						WHERE ba.attribute = <<cobrador>> 
						AND al.accounttype='pay' AND al.description = CONCAT('Cobrado por ' ,ba.attribute)
						AND YEAR(al.date) = <<anio>> AND MONTH(al.date)= <<mes>>",
					notes => "Con este informe puede conocer cuanto falta por cobrar. "};
			foreach (@reportes){
				
=cut
