
<h1 id="logo"><a href="/cgi-bin/koha/mainpage.pl"><!-- TMPL_VAR NAME="LibraryName" --></a></h1><!-- Begin Circulation Resident Search Box -->

<div id="header_search">
    
<div id="fees_search" class="residentsearch" >
    <form >
    <label for="borrower" class="tip">Ingrese el numero de socio</label><br/>
  <INPUT type="text" name="borrower" id="borrower" class="focus">    
  <br/> <input type="submit" name="action" name="action"  class="submit" value="Cobrar a un socio"/>
            
    </form>
    </div>
<!-- TMPL_INCLUDE NAME="patron-search-box.inc" -->

<div id="fees_pc"  >
		<ul id="panel_control">
			<li><a href="/cgi-bin/koha/fees/fees.pl">
			<img src="/intranet-tmpl/prog/img/fees/socio.png"/><div>Socios</div></a>
			</li>
			<li><a href="/cgi-bin/koha/fees/fees.pl?action=collectors">
			<img src="/intranet-tmpl/prog/img/fees/cobrador.png"/><div>Cobradores</div></a>
			</li>
			<li><a href="/cgi-bin/koha/fees/fees.pl?action=form+generar+cuotas">
			<img src="/intranet-tmpl/prog/img/fees/cuotas.png"/><div>Generar cuotas</div></a>
			</li>
			<li><a href="/cgi-bin/koha/fees/fees.pl?action=otros">
			<img src="/intranet-tmpl/prog/img/fees/otros.png"/><div>otros</div></a>
			</li>
			<li><a href="/cgi-bin/koha/fees/fees.pl?action=configurar+modulo">
			<img src="/intranet-tmpl/prog/img/fees/config.png"/><div>Configurar</div></a>
			</li>

		</ul>
    </div>

<ul>
    <li><a href="#fees_search">Cobrar a socios</a></li>
    <!-- TMPL_IF NAME="CAN_user_circulate" --><li><a href="/cgi-bin/koha/circ/circulation.pl#circ_search">Préstamo</a></li><!-- /TMPL_IF -->
    <li><a href="#fees_pc">Menu</a></li>
</ul>   

</div>

<!-- End Circulation Resident Search Box -->
