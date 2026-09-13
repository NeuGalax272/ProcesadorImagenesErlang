-module(startup).
-export([lector/1]).
-export([escritor/2]).
-export([dividir/3]).
-export([reconstruir/4]).
-export([trabajador/3]).
-export([procesarImagen/4]).

 %lee la imagen y separa los valores
lector(Filename) -> {ok, Binario} = file:read_file(Filename), parsear(string:tokens(binary_to_list(Binario), " \t\r\n")).
%genera la tupla para procesar cada parte
parsear(["P3", AnchoStr, AltoStr, MaxStr | TokensPixeles]) -> Ancho = list_to_integer(AnchoStr),
	   Alto = list_to_integer(AltoStr), Max = list_to_integer(MaxStr),
	   {image, Ancho, Alto, Max, armarFilas(Ancho, armarPixeles(TokensPixeles))}.
	
%aqui se empiezan a armar los RGB
armarPixeles([]) -> [];
armarPixeles([RStr, GStr, BStr | Resto]) ->  [{list_to_integer(RStr), list_to_integer(GStr), list_to_integer(BStr)} | armarPixeles(Resto)].
	
%agarra el ancho y los pixeles para hacer las filas
armarFilas(_Ancho, []) -> [];
armarFilas(Ancho, Pixeles) -> {Fila, Resto} = lists:split(Ancho, Pixeles), [Fila | armarFilas(Ancho, Resto)].
	
    
%para ir escribiendo la imagen
escritor(Filename, {image, Ancho, Alto, Max, Filas}) -> file:write_file(Filename, [cabecera(Ancho, Alto, Max) | formatoFilas(Filas)]).
%escribe la cabecera de PPM
cabecera(Ancho, Alto, Max) -> io_lib:format("P3~n~b ~b~n~b~n", [Ancho, Alto, Max]).
%solo para poner el \n en cada fila
formatoFilas([]) -> [];
formatoFilas([Fila | Resto]) -> [formatoFila(Fila), "\n" | formatoFilas(Resto)].

%agarra las listas de tuplas de RGB y las pasa a texto
formatoFila([{R,G,B}]) -> io_lib:format("~b ~b ~b", [R, G, B]);
formatoFila([{R,G,B} | Resto]) -> [io_lib:format("~b ~b ~b  ", [R, G, B]) | formatoFila(Resto)].
	
	
%aqui ya se divide la imagen en zonas iguales
dividir({image, Ancho, Alto, Max, Filas}, NumProcesos, TamanoKernel) -> TamanoHalo = TamanoKernel div 2,
	Tamanos = calcularTamanos(Alto, NumProcesos), Bloques = dividirEnBloques(Filas, Tamanos),
	{Ancho, Alto, Max, armarZonas(Bloques, TamanoHalo)}.
	
%calcula la altura de la imagen y las zonas a dividir
calcularTamanos(Alto, NumProcesos) -> distribuirTamanos(NumProcesos, Alto div NumProcesos, Alto rem NumProcesos).

distribuirTamanos(0, _Base, _Resto) -> [];
distribuirTamanos(N, Base, 0) -> [Base | distribuirTamanos(N-1, Base, 0)];
distribuirTamanos(N, Base, Resto) -> [Base+1 | distribuirTamanos(N-1, Base, Resto-1)].
	
%esto es para el 'halo', agarra de las zonas vecinas
tomarPrimeros(_, 0) -> [];
tomarPrimeros([], _) -> [];
tomarPrimeros([X | Resto], N) -> [X | tomarPrimeros(Resto, N-1)].

tomarUltimos(Lista, N) -> lists:reverse(tomarPrimeros(lists:reverse(Lista), N)).

%divide las zonas
dividirEnBloques(_Filas, []) -> [];
dividirEnBloques(Filas, [Tamano | RestoTamanos]) -> {Bloque, Resto} = lists:split(Tamano, Filas),
	[Bloque | dividirEnBloques(Resto, RestoTamanos)].

%arma las zonas
armarZonas(Bloques, TamanoHalo) -> armarZonasAux(Bloques, TamanoHalo, [], 1).

armarZonasAux([], _TamanoHalo, _BloqueAnterior, _Indice) -> [];
armarZonasAux([Bloque], TamanoHalo, BloqueAnterior, Indice) -> [{region, Indice, Bloque, tomarUltimos(BloqueAnterior, TamanoHalo), []}];
armarZonasAux([Bloque | RestoBloques], TamanoHalo, BloqueAnterior, Indice) -> SiguienteBloque = hd(RestoBloques), [{region, Indice, Bloque, tomarUltimos(BloqueAnterior, TamanoHalo), tomarPrimeros(SiguienteBloque, TamanoHalo)} | armarZonasAux(RestoBloques, TamanoHalo, Bloque, Indice+1)].
	
	
%reconstructor
reconstruir(Ancho, Alto, Max, Resultados) -> {image, Ancho, Alto, Max,      concatenarFilas(ordenarPorIndice(Resultados))}.  

%ordena la lista de tuplas por indice
ordenarPorIndice(Resultados) -> lists:keysort(1, Resultados).

%y esta quita el indice y las cocatena
concatenarFilas([]) -> [];
concatenarFilas([{_Indice, Filas} | Resto]) -> Filas ++ concatenarFilas(Resto).
	
	
%aqui se empiezan los trabajadores y la conexion con scheme
trabajador(Zona, ParametrosFiltro, PidCoordinador) ->{region, Indice, Bloque, HaloArriba, HaloAbajo} = Zona,
	FilasProcesadas = aplicarFiltro(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro),
	PidCoordinador ! {resultado, Indice, FilasProcesadas}.

%aqui se hace la llamada a scheme, por ahora un placeholder
aplicarFiltro(_HaloArriba, Bloque, _HaloAbajo, _ParametrosFiltro) ->  Bloque.

%aqui ya se hacen los 'spawn' de los procesos por region
crearProcesos([], _ParametrosFiltro, _PidCoordinador) -> ok;
crearProcesos([Zona | RestoZonas], ParametrosFiltro, PidCoordinador) ->
	spawn(fun() -> trabajador(Zona, ParametrosFiltro, PidCoordinador) end),
	crearProcesos(RestoZonas, ParametrosFiltro, PidCoordinador).

%aqui termina lo procesado por scheme
recibirResultados(0) -> [];
recibirResultados(N) ->receive{resultado, Indice, Filas} ->[{Indice, Filas} | recibirResultados(N-1)]  end.

		
%este ya seria el 'main'
procesarImagen(ArchivoEntrada, ArchivoSalida, NumProcesos, TamanoKernel) -> Img = lector(ArchivoEntrada),
	{Ancho, Alto, Max, Zonas} = dividir(Img, NumProcesos, TamanoKernel),
	crearProcesos(Zonas, TamanoKernel, self()),
	Resultados = recibirResultados(length(Zonas)),
	Reconstruida = reconstruir(Ancho, Alto, Max, Resultados),
	escritor(ArchivoSalida, Reconstruida).
	

	

