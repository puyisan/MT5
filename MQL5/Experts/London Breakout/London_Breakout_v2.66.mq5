//+------------------------------------------------------------------+
//|                    London_Breakout_v2.66.mq5                     |
//|        Ruptura del Rango de Londres — US30 — Nueva York          |
//|                     Copyright 2026, RRL Strategy                 |
//+------------------------------------------------------------------+
#property copyright "RRL Strategy"
#property version   "2.66"
#property description "London Breakout US30 — v2.66"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//+------------------------------------------------------------------+

input group "=== RIESGO Y BALAS ==="
input double RiskPerBala       = 0.5;  // Riesgo por bala (% balance)
input double MaxDailyLossPct   = 2.0;  // Limite maximo de perdida diaria (% balance)
input double MaxDailyProfitPct = 3.0;  // Limite maximo de ganancia diaria (% balance)
                                        // 0 = desactivado (sin limite de ganancia)
input double ReservaDeslizamientoPct = 0.0; // Reserva (% balance) para deslizamiento del SL
                                        // Se resta del presupuesto diario: con 0.25 y
                                        // limite 2%, la ultima bala solo sale si quedan
                                        // 0.5% + 0.25% libres. 0 = sin reserva (v2.65)
input double LoteMinBroker     = 0.01; // Lote minimo permitido por el broker
input double ValorPuntoPorLote = 1.0;  // [Respaldo] Valor en USD de 1 pip por lote
                                        // v2.66: el lote se calcula con OrderCalcProfit
                                        // (valor real del simbolo). Este parametro solo
                                        // se usa si OrderCalcProfit falla.
                                        //
                                        // Como calcularlo: abre 1 lote manualmente,
                                        // mueve el precio 1 punto y observa el P&L.
                                        // Ese valor es ValorPuntoPorLote.
                                        //
                                        // Ejemplos comunes en US30:
                                        //   Broker A: 1 lote × 1 punto = $1   → poner 1.0
                                        //   Broker B: 1 lote × 1 punto = $10  → poner 10.0
                                        //   Broker C: 1 lote × 1 punto = $100 → poner 100.0
input int    PuntosPerPip      = 100;  // Puntos por pip segun el broker
                                        // Define cuantos _Point equivalen a 1 pip
                                        // Con _Point=0.01 y PuntosPerPip=100:
                                        //   pipSize = 0.01 × 100 = 1.0
                                        //   1 pip = 1 punto del indice ← US30 estandar
                                        // Con _Point=0.01 y PuntosPerPip=10:
                                        //   pipSize = 0.01 × 10 = 0.10
                                        //   1 pip = 0.1 puntos del indice
input double StopLossPips      = 50.0; // Stop Loss en puntos del indice
                                        // Con PuntosPerPip=100: 50 pips = 50 puntos
input double TP1Pips           = 100.0;// Take Profit entrada 1 (puntos del indice)
input double TP2Pips           = 200.0;// Take Profit entrada 2 (puntos del indice)

input group "=== ENTRADA Y SPREAD ==="
input double OffsetEntradaPips  = 1.0;  // Distancia de la entrada al rango (pips). v2.65 = 1
input bool   CompensarSpreadBuy = true; // [true] BuyStop = alto + offset + spread actual
                                        // La BuyStop se ejecuta con el ASK: sin compensar,
                                        // salta antes de que el BID rompa el rango.
                                        // [false] = comportamiento de v2.65
input double MaxSpreadPips      = 0.0;  // Spread maximo para lanzar una bala (pips)
                                        // 0 = sin filtro

input group "=== CHECKPOINTS (por bala) ==="
input double CP1Pips           = 50.0; // CP1: Break Even (puntos del indice)
input double CP3Pips           = 150.0;// CP3: SP entrada 2 a +100 puntos
input double CP3_TrailingPips  = 50.0; // Trailing Stop desde CP3 (puntos)
input double TrailingPasoPips  = 5.0;  // Mejora minima para mover el trailing (puntos)
                                        // v2.66: evita un PositionModify por tick
input bool   UseTrailingCP3    = true;  // [true] TS activo desde CP3
input bool   RemoveTP2atCP4    = false; // [true] En TP2 elimina el TP y dejacorrer el TS 
					// captura movimientos mayores
                                        // [false] Cierra E2 en TP2 (+200) fijo sin excepcion

input group "=== CONFIRMACION DE REINGRESO ==="
input bool   UsarConfirmacion  = true; // Activar confirmacion de reingreso
input int    VelasConfirmacion = 1;    // Velas M1 con cierre DENTRO del rango
                                        // Requeridas antes de lanzar la siguiente bala.
                                        // El cierre de la vela debe estar entre rangeLow y rangeHigh.
                                        // 0 = sin confirmacion (reingreso inmediato)
                                        // 1 = 1 vela (recomendado, balance velocidad/seguridad)
                                        // 2-3 = mas conservador, menos reingresos

input group "=== FILTROS DE DIAS ==="
input bool   TradeMonday       = true;
input bool   TradeTuesday      = true;
input bool   TradeWednesday    = true;
input bool   TradeThursday     = true;
input bool   TradeFriday       = true;
input int    VentanaViernesPips = 3;   // Horas de ventana NY los viernes
input bool   FiltrarFestivosUS = true; // No operar en festivos de EE.UU.
input bool   FiltrarFestivosUK = true; // No operar en festivos de Reino Unido (Bank Holidays)

input group "=== CONFIGURACION ==="
input int    MagicNumber       = 80082505;
input string TradeComment      = "RRL_US30";

input group "=== HORARIOS ==="
// v2.66: regla de horario de verano del BROKER (solo con UsarDSTAutomatico=true)
enum ENUM_DST_BROKER
{
   DST_BROKER_AUTO    = 0, // Auto: detectar offset en vivo (tester: regla Europa)
   DST_BROKER_EUROPA  = 1, // Europa: +1h de ultimo domingo marzo a ultimo domingo octubre
   DST_BROKER_EEUU    = 2, // EE.UU.: +1h de 2do domingo marzo a 1er domingo noviembre
   DST_BROKER_NINGUNO = 3  // Sin cambio de hora (offset fijo = GMT_Broker_Base)
};
input bool   UsarDSTAutomatico = true;  // true  = calcula DST automaticamente
                                         //         solo necesitas GMT_Broker_Base
                                         // false = usa los GMT manuales definidos abajo
input int    GMT_Broker_Base   = 2;     // Offset GMT base del broker SIN DST
                                         // Ej: broker Europa = 2 (invierno)
                                         //     broker UTC    = 0 (nunca cambia)
input ENUM_DST_BROKER ModoDSTBroker = DST_BROKER_AUTO; // Regla DST del broker
                                         // Muchos brokers GMT+2/+3 cambian con EE.UU.
                                         // (17:00 NY = 00:00 servidor). En el tester
                                         // elige EUROPA o EEUU segun tu broker.
input int    CierreViernesBroker = 22;  // Hora BROKER de cierre/reset los viernes
                                         // (-1 = usar el cierre normal GMT_NYCierra)
// --- Solo si UsarDSTAutomatico = false ---
input int    GMT_Broker_Manual = 2;     // [Manual] GMT actual del broker
input int    GMT_Londres_Manual= 0;     // [Manual] GMT actual de Londres (0=GMT, 1=BST)
input int    GMT_NY_Manual     = -5;    // [Manual] GMT actual de NY (-5=EST, -4=EDT)
// --- Horario de operacion (en GMT, el bot convierte al broker) ---
input int    GMT_LondresAbre   = 8;     // Hora GMT apertura Londres (normalmente 8)
input int    GMT_LondresCierra = 16;    // Hora GMT cierre ventana Londres/inicio NY
                                         // (normalmente 16 = 1 min antes de NY open)
input int    GMT_NYAbre        = 14;    // Hora GMT apertura NY (09:00 NY = 14:00 GMT)
input int    GMT_VentanaCierra = 18;    // Hora GMT cierre ventana de operacion (NY+4h)
input int    GMT_NYCierra      = 21;    // Hora GMT cierre mercado NY / reset diario

input group "=== ALERTAS TELEGRAM ==="
input bool   TelegramEnabled   = true;            // Activar alertas Telegram
input string TelegramToken     = "TU_BOT_TOKEN";  // Token del bot de Telegram
input string TelegramChatID    = "TU_CHAT_ID";    // Chat ID de Telegram

input group "=== NIVELES DE CP's y TP's ==="
input bool             NivelesVisible    = true;           // Mostrar niveles en el grafico
input int              NvlGrosor         = 1;              // Grosor de todas las lineas (1-5)
input ENUM_LINE_STYLE  NvlEstilo         = STYLE_DASH;     // Estilo de todas las lineas
// --- Colores individuales por nivel ---
input color            NvlClrEntrada     = C'220,220,220'; // Color: Entrada (Buy / Sell)
input color            NvlClrSL         = C'255,70,70';   // Color: Stop Loss
input color            NvlClrCP1        = C'255,215,50';  // Color: CP1
input color            NvlClrTP1        = C'100,220,140'; // Color: TP1
input color            NvlClrCP3        = C'60,180,255';  // Color: CP3
input color            NvlClrTP2        = C'0,230,120';   // Color: TP2

input group "=== RANGO LONDRES — VISUAL ==="
input bool             RangoVisible      = true;              // Mostrar marco del rango en el grafico
input color            RangoColorLinea   = C'100,160,255';    // Color de las lineas del marco
input int              RangoGrosor       = 1;                 // Grosor de las lineas (1-5)
input ENUM_LINE_STYLE  RangoEstilo       = STYLE_DASH;        // Estilo de linea del marco
input bool             RangoRelleno      = false;              // Rellenar el area del rango con color
input color            RangoColorRelleno = C'100,160,255';    // Color del relleno
input int              RangoOpacidad     = 15;                // Opacidad del relleno (1-100)

input group "=== LINEAS VERTICALES — VISUAL ==="
input bool             VLinNYVisible     = true;              // Mostrar linea LBO Open
input color            VLinNYColor       = clrBlack;      // Color: LBO Open
input int              VLinNYGrosor      = 1;                 // Grosor: LBO Open
input ENUM_LINE_STYLE  VLinNYEstilo      = STYLE_DASH;        // Estilo: LBO Open
input bool             VLinCierreVisible = true;              // Mostrar linea LBO Close
input color            VLinCierreColor   = clrBlack;    // Color: LBO Close
input int              VLinCierreGrosor  = 1;                 // Grosor: LBO Close
input ENUM_LINE_STYLE  VLinCierreEstilo  = STYLE_DASH;        // Estilo: LBO Close

input group "=== DASHBOARD ==="
input bool   DashVisible       = true;             // Mostrar dashboard en el grafico
input string DashFuente        = "Consolas";       // Fuente del dashboard
input int    DashTamano        = 8;                // Tamaño de letra (8-12 recomendado)
input int    DashAncho         = 238;              // Ancho del panel en pixeles
input int    DashAltoFila      = 16;               // Alto de cada fila en pixeles
input int    DashPosX          = 10;               // Posicion X (pixeles desde borde)
input int    DashPosY          = 25;               // Posicion Y (pixeles desde borde)
// --- Colores del dashboard ---
input color  DashClrFondo      = C'18,20,32';      // Color: fondo del panel
input color  DashClrBorde      = C'55,60,85';      // Color: borde del panel
input color  DashClrTitulo     = C'255,200,0';     // Color: titulo principal
input color  DashClrSeccion    = C'130,170,255';   // Color: cabeceras de seccion
input color  DashClrTexto      = C'210,210,210';   // Color: texto normal
input color  DashClrValor      = C'245,245,245';   // Color: valores resaltados
input color  DashClrVerde      = C'70,210,110';    // Color: positivo / OK
input color  DashClrRojo       = C'255,75,75';     // Color: negativo / alerta
input color  DashClrAmarillo   = C'255,215,50';    // Color: advertencia / activo
input color  DashClrGris       = C'110,115,135';   // Color: inactivo / pendiente


//+------------------------------------------------------------------+
//| ESTRUCTURA DE BALA                                               |
//+------------------------------------------------------------------+
struct Bala
{
   int    id;
   int    direction;    // 1=Buy, -1=Sell, 0=pendiente
   bool   active;       // Posiciones abiertas actualmente
   bool   e2Abierta;    // Segunda entrada ya fue abierta (proteccion anti-duplicado)
   bool   cp1Done;
   bool   tp1Done;
   bool   cp3Done;
   bool   tp2Done;
   bool   terminada;    // La bala ya cerro completamente
   string resultado;   // "TP", "BE", "SP", "SL", "NA" — resultado final de la bala
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo posInfo;

// Zona horaria
int brokerOffsetHours = 0;
int londonStartH = 0, londonStartM = 0;
int londonEndH   = 0, londonEndM   = 0;
int nyOpenH      = 0;
int cancelH      = 0;
int closeAllH    = 0;

// Rango diario
double rangeHigh  = 0;
double rangeLow   = 0;
bool   rangeSet   = false;
bool   rangeFijado= false; // true = rango definitivo al cerrar sesion Londres
bool   rangoEnVivo= false; // true = la sesion de Londres se siguio en vivo hoy (v2.66)

// Sistema de balas
Bala   balas[8];
int    balaActual       = 0;
bool   balaEnCurso      = false;
datetime horaprimeraBala = 0;  // hora en que se lanzo la primera bala del dia
int    balasConSL       = 0;
int    balasConTP       = 0;
int    balasConBE       = 0;
int    balasConSP       = 0;
double balanceInicioDia = 0;
datetime inicioDiaOperativo = 0; // inicio del dia de trading (reset diario o medianoche) — v2.66

// Confirmacion de reingreso
bool   esperandoConfirmacion = false; // true = bala termino, esperando velas dentro del rango
int    velasConfirmadas      = 0;     // contador de velas M1 cerradas dentro del rango
datetime ultimaVelaContada  = 0;     // timestamp de la ultima vela ya contada (evita doble conteo)

int    currentDay    = -1;
double pipSize       = 0;
int    symDigits     = 0;   // Digitos del simbolo (renombrado para evitar conflicto con librerias)

// Control de rendimiento en OnTick
int    lastPanelMin      = -1;
int    lastRangeMin      = -1;   // ultimo minuto en que se actualizo el rango
bool   cierreNYHecho     = false;
bool   nivelesNYDibujados = false; // true = niveles ya dibujados al inicio de NY
bool   londresIniciadoAlertado = false;
bool   cierreNYAlertado  = false; // true = alerta cierre NY ya enviada
bool   resetEjecutado    = false; // flag externo que sobrevive al ResetDaily
bool   reinicioTemporal  = false; // true = reinicio por cambio temporalidad/parametros

// Estado del panel y bot
bool   botPausado        = false; // true = no lanza nuevas balas
bool   precioFueraRango  = false; // true = precio salio del rango, esperar reingreso
bool   panelMinimizado   = false; // true = panel colapsado a solo titulo
int    opuestaAlertadaBala = -1;  // bala (1-8) con alerta de "ambas direcciones" ya enviada

// Flags de festivo — calculados una vez al dia en RecalcHours
bool   esFestivoHoyUS   = false;
bool   esFestivoHoyUK   = false;
bool   festivoAlertado   = false; // mensaje Telegram festivo enviado hoy
bool   esFestMananUS    = false;
bool   esFestMananUK    = false;

// Cache de PnL — calculado una vez por tick y reutilizado
double cachePnLPct       = 0;
int    cachePnLMin       = -1;

// Cache de ContarBalasHoy — calculado una vez por minuto
int    cacheBalasHoy     = 0;
int    cacheBalasHoyMin  = -1;

// Cache de datos del simbolo — calculados en OnInit y no cambian
double symMinLot         = 0;
double symMaxLot         = 0;
double symLotStep        = 0;

// Flags de alertas diarias (antes declarados al final del archivo)
bool   limiteDiarioAlertado = false; // alerta de limite diario ya enviada hoy
bool   tpDiarioAlcanzado    = false; // true = ganancia diaria maxima alcanzada

// Contadores de checkpoints alcanzados en el dia (para el CSV)
int    statCP1           = 0;
int    statTP1           = 0;
int    statCP3           = 0;
int    statTP2           = 0;

//+------------------------------------------------------------------+
//| ZONA HORARIA Y DST                                               |
//+------------------------------------------------------------------+

// Calcular el ultimo domingo de un mes/año dado
datetime UltimoDomingoDelMes(int anio, int mes)
{
   // Empezar desde el ultimo dia del mes y retroceder hasta encontrar domingo
   int diasMes[13] = {0,31,28,31,30,31,30,31,31,30,31,30,31};
   bool bisiesto = (anio%4==0 && anio%100!=0) || (anio%400==0);
   if(bisiesto) diasMes[2] = 29;

   for(int d = diasMes[mes]; d >= 1; d--)
   {
      MqlDateTime dt;
      TimeToStruct(StringToTime(StringFormat("%04d.%02d.%02d", anio, mes, d)), dt);
      if(dt.day_of_week == 0) // 0 = domingo
         return StringToTime(StringFormat("%04d.%02d.%02d 01:00:00", anio, mes, d));
   }
   return 0;
}

// Calcular el N-esimo domingo de un mes/año dado (ej. segundo domingo = N=2)
datetime NesimosDomingoDelMes(int anio, int mes, int n)
{
   int count = 0;
   for(int d = 1; d <= 31; d++)
   {
      string fechaStr = StringFormat("%04d.%02d.%02d", anio, mes, d);
      datetime t = StringToTime(fechaStr);
      if(t == 0) break;
      MqlDateTime dt;
      TimeToStruct(t, dt);
      if(dt.mon != mes) break;
      if(dt.day_of_week == 0) // domingo
      {
         count++;
         if(count == n)
            return StringToTime(StringFormat("%04d.%02d.%02d 02:00:00", anio, mes, d));
      }
   }
   return 0;
}

// Verificar si una fecha esta en horario de verano de Londres (BST)
// BST: ultimo domingo de marzo 01:00 UTC → ultimo domingo de octubre 01:00 UTC
bool EsBST(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   datetime inicioBST = UltimoDomingoDelMes(dt.year, 3);
   datetime finBST    = UltimoDomingoDelMes(dt.year, 10);
   return (t >= inicioBST && t < finBST);
}

// Verificar si una fecha esta en horario de verano de NY (EDT)
// EDT: segundo domingo de marzo 02:00 → primer domingo de noviembre 02:00
bool EsEDT(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   datetime inicioEDT = NesimosDomingoDelMes(dt.year, 3,  2); // 2do domingo marzo
   datetime finEDT    = NesimosDomingoDelMes(dt.year, 11, 1); // 1er domingo noviembre
   return (t >= inicioEDT && t < finEDT);
}

// Obtener offset GMT actual de Londres (0 en invierno, 1 en verano BST)
int GetGMTLondres()
{
   if(!UsarDSTAutomatico) return GMT_Londres_Manual;
   return EsBST(TimeGMT()) ? 1 : 0;
}

// Obtener offset GMT actual de NY (-5 en invierno, -4 en verano EDT)
int GetGMTNY()
{
   if(!UsarDSTAutomatico) return GMT_NY_Manual;
   return EsEDT(TimeGMT()) ? -4 : -5;
}

// Obtener offset GMT actual del broker
// Brokers europeos: GMT_Broker_Base en invierno, +1 en verano (siguen DST europeo = BST)
// Si UsarDSTAutomatico: GMT_Broker_Base + 1 si Londres esta en BST
// Si manual: usar GMT_Broker_Manual
// v2.66: detectar el offset real del servidor en cuenta real/demo.
// TimeTradeServer() - TimeGMT() depende de que la zona horaria del PC sea correcta.
bool DetectarOffsetBrokerEnVivo(int &offset)
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
   datetime srv = TimeTradeServer();
   datetime gmt = TimeGMT();
   if(srv <= 0 || gmt <= 0) return false;
   double horas = (double)((long)srv - (long)gmt) / 3600.0;
   int    h     = (int)MathRound(horas);
   if(h < -12 || h > 14)          return false;
   if(MathAbs(horas - h) > 0.25)  return false; // desfase no entero: reloj poco fiable
   offset = h;
   return true;
}

int GetGMTBroker()
{
   if(!UsarDSTAutomatico) return GMT_Broker_Manual;
   datetime gmt = TimeGMT();
   if(ModoDSTBroker == DST_BROKER_EEUU)    return GMT_Broker_Base + (EsEDT(gmt) ? 1 : 0);
   if(ModoDSTBroker == DST_BROKER_NINGUNO) return GMT_Broker_Base;
   if(ModoDSTBroker == DST_BROKER_AUTO)
   {
      int detectado = 0;
      if(DetectarOffsetBrokerEnVivo(detectado))
      {
         int reglaEU = GMT_Broker_Base + (EsBST(gmt) ? 1 : 0);
         if(detectado != reglaEU)
            Print("[HORARIOS] Offset del servidor detectado GMT", detectado >= 0 ? "+" : "", detectado,
                  " (la regla europea daria GMT+", reglaEU, "). Se usa el detectado.");
         return detectado;
      }
      // Tester o deteccion fallida: regla europea (comportamiento de v2.65)
   }
   // DST_BROKER_EUROPA: la mayoria de brokers europeos siguen el DST de Europa (= BST)
   return GMT_Broker_Base + (EsBST(gmt) ? 1 : 0);
}

// Convertir hora GMT a hora del broker
int GMTtoBroker(int gmtHour)
{
   int h = gmtHour + brokerOffsetHours;
   while(h >= 24) h -= 24;
   while(h <  0)  h += 24;
   return h;
}

// Detectar offset del broker (para compatibilidad con codigo existente)
int DetectBrokerGMTOffset()
{
   return GetGMTBroker();
}

void RecalcHours()
{
   // Obtener el GMT actual del broker (automatico o manual)
   brokerOffsetHours = GetGMTBroker();

   // Obtener GMT actual de Londres y NY (con o sin DST)
   int gmtLondres = GetGMTLondres();
   int gmtNY      = GetGMTNY();

   // Los parametros GMT_* son las horas GMT en horario de INVIERNO (EST/GMT)
   // Con DST automatico, se ajustan segun el horario de verano activo
   int gmtLondresAbre   = GMT_LondresAbre;
   int gmtNYAbre        = GMT_NYAbre;
   int gmtVentanaCierra = GMT_VentanaCierra;
   int gmtNYCierra      = GMT_NYCierra;

   if(UsarDSTAutomatico)
   {
      // Londres en BST (verano): abre 1h antes en GMT
      // GMT_LondresAbre=8 (invierno) → 7 (verano BST)
      if(EsBST(TimeGMT())) gmtLondresAbre -= 1;

      // NY en EDT (verano): abre 1h antes en GMT
      // GMT_NYAbre=14 (invierno EST) → 13 (verano EDT)
      // Lo mismo aplica a ventana y cierre
      if(EsEDT(TimeGMT()))
      {
         gmtNYAbre        -= 1;
         gmtVentanaCierra -= 1;
         gmtNYCierra      -= 1;
      }
   }

   // Convertir horas GMT al horario del broker
   londonStartH = GMTtoBroker(gmtLondresAbre);   londonStartM = 0;
   londonEndH   = GMTtoBroker(gmtNYAbre - 1);    londonEndM   = 59; // NY open - 1 min
   nyOpenH      = GMTtoBroker(gmtNYAbre);
   cancelH      = GMTtoBroker(gmtVentanaCierra);
   closeAllH    = GMTtoBroker(gmtNYCierra);

   Print("[HORARIOS] Modo: ", UsarDSTAutomatico ? "AUTOMATICO (" + EnumToString(ModoDSTBroker) + ")" : "MANUAL",
         " | GMT Broker:", brokerOffsetHours,
         " GMT Londres:", gmtLondres,
         " GMT NY:", gmtNY);
   Print("[HORARIOS] Broker time → Londres:", londonStartH, ":00-", londonEndH,
         ":59 | NY:", nyOpenH, ":00-", cancelH, ":00 | Cierre:", closeAllH, ":00");

   // Calcular flags de festivo para hoy y mañana — una sola vez al dia
   MqlDateTime dtHoy, dtMan;
   TimeToStruct(TimeCurrent(), dtHoy);
   TimeToStruct(TimeCurrent() + 86400, dtMan);
   esFestivoHoyUS = EsFestivoUS(dtHoy);
   esFestivoHoyUK = EsFestivoUK(dtHoy);
   esFestMananUS  = EsFestivoUS(dtMan);
   esFestMananUK  = EsFestivoUK(dtMan);

   if(esFestivoHoyUS) Print("[FESTIVO] Hoy es festivo US — sin operativa.");
   if(esFestivoHoyUK) Print("[FESTIVO] Hoy es festivo UK — sin operativa.");
}

//+------------------------------------------------------------------+
//| RECUPERAR ESTADO DEL DIA DESDE HISTORIAL DE DEALS        |
//| Llamado en OnInit y en cada reset diario                         |
//| Reconstruye: balanceInicioDia, balaActual, balasConSL, balasConTP|
//+------------------------------------------------------------------+
void RecuperarEstadoDesdHistorial()
{
   // Calcular inicio del dia actual usando aritmetica directa
   // (evita dependencia de configuracion regional del broker)
   datetime ahora = TimeCurrent();
   MqlDateTime dtA;
   TimeToStruct(ahora, dtA);
   datetime hoy    = ahora - dtA.hour * 3600 - dtA.min * 60 - dtA.sec;
   datetime manana = hoy + 86400;

   // Seleccionar historial del dia actual
   if(!HistorySelect(hoy, manana)) return;

   // Reconstruir balance inicio del dia
   double pnlDiaUSD = 0;
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)    continue;
      // v2.66: todos los deals de trading (la comision puede cobrarse en la entrada)
      long tipoDeal = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(tipoDeal != DEAL_TYPE_BUY && tipoDeal != DEAL_TYPE_SELL) continue;
      pnlDiaUSD += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                +  HistoryDealGetDouble(ticket, DEAL_SWAP)
                +  HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                +  HistoryDealGetDouble(ticket, DEAL_FEE);
   }
   double balanceActual = AccountInfoDouble(ACCOUNT_BALANCE);
   // Si hubo deals cerrados, el balance inicio = balance actual - lo ganado/perdido
   balanceInicioDia = (pnlDiaUSD != 0) ? balanceActual - pnlDiaUSD : balanceActual;

   // v2.66: identificar cada bala por el comentario del deal de ENTRADA.
   // Los deals de salida por SL/TP llevan el comentario del servidor
   // ("[sl ...]", "[tp ...]"), por eso se asocian a su entrada via DEAL_POSITION_ID.
   bool   bVista[8]  = {false, false, false, false, false, false, false, false};
   bool   bActiva[8] = {false, false, false, false, false, false, false, false};
   bool   bSL[8]     = {false, false, false, false, false, false, false, false};
   bool   bBE[8]     = {false, false, false, false, false, false, false, false};
   bool   bSP[8]     = {false, false, false, false, false, false, false, false};
   bool   bTP[8]     = {false, false, false, false, false, false, false, false};
   string e1Res[8];
   for(int b = 0; b < 8; b++) e1Res[b] = "";

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != MagicNumber) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)     continue;

      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry == DEAL_ENTRY_IN)
      {
         int bIn = NumeroBalaDeComentario(HistoryDealGetString(ticket, DEAL_COMMENT));
         if(bIn >= 1) bVista[bIn-1] = true;
         continue;
      }
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      double precioEntrada = 0;
      string cmt = TagDealSalida(ticket, precioEntrada);
      int bOut = NumeroBalaDeComentario(cmt);
      if(bOut < 1) continue;

      bVista[bOut-1] = true;
      string res = ClasificarDealSalida(ticket, precioEntrada);
      if(res == "SL")      bSL[bOut-1] = true;
      else if(res == "BE") bBE[bOut-1] = true;
      else if(res == "SP") bSP[bOut-1] = true;
      else if(res == "TP") bTP[bOut-1] = true;
      if(StringFind(cmt, "_E1") >= 0) e1Res[bOut-1] = res;
   }

   // Balas con posiciones u ordenes activas AHORA
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)     continue;
      int bP = NumeroBalaDeComentario(posInfo.Comment());
      if(bP >= 1) bActiva[bP-1] = true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      int bO = NumeroBalaDeComentario(OrderGetString(ORDER_COMMENT));
      if(bO >= 1) bActiva[bO-1] = true;
   }

   // La bala actual es la de numero mas alto vista hoy (las balas son correlativas)
   int maxBala = 0;
   for(int b = 0; b < 8; b++)
      if(bVista[b] || bActiva[b]) maxBala = b + 1;

   balasConSL  = 0;
   balasConTP  = 0;
   balasConBE  = 0;
   balasConSP  = 0;
   balaEnCurso = false;

   for(int b = 0; b < maxBala; b++)
   {
      if(bActiva[b])
      {
         balas[b].active    = true;
         balas[b].terminada = false;
         balas[b].tp1Done   = (e1Res[b] == "TP");
         balas[b].cp1Done   = balas[b].tp1Done;

         // Inferir CP1/CP3 por el SL actual de las posiciones abiertas (con signo)
         string tagB = "_B" + IntegerToString(b+1) + "_";
         int    nPos = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!posInfo.SelectByIndex(i)) continue;
            if(posInfo.Magic()  != MagicNumber) continue;
            if(posInfo.Symbol() != _Symbol)     continue;
            string cmtP = posInfo.Comment();
            if(StringFind(cmtP, tagB) < 0) continue;
            nPos++;
            bool   isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
            if(balas[b].direction == 0) balas[b].direction = isBuy ? 1 : -1;
            double sl    = posInfo.StopLoss();
            if(sl == 0) continue;
            double openP = posInfo.PriceOpen();
            // Positivo = SL en zona de ganancia, negativo = SL en zona de perdida
            double slPips = isBuy ? (sl - openP) / pipSize : (openP - sl) / pipSize;
            if(slPips >= -0.5) balas[b].cp1Done = true;          // BE o mejor
            if(StringFind(cmtP, "_E2") >= 0 && slPips >= CP3Pips - CP1Pips - 5.0)
            {
               balas[b].cp3Done = true;
               balas[b].cp1Done = true;
            }
         }
         balas[b].e2Abierta = (nPos >= 2);
         balaEnCurso = true;
         continue;
      }

      if(!bVista[b]) continue; // bala sin deals: nunca se activo

      // Bala terminada — misma prioridad que ManageCheckpointsBala: SL > BE > SP > TP
      string res;
      if(bSL[b])                          res = "SL";
      else if(!bTP[b] && !bSP[b] && bBE[b]) res = "BE";
      else if(bSP[b])                     res = "SP";
      else if(bTP[b])                     res = "TP";
      else                                res = "NA"; // solo cierres manuales

      balas[b].active    = false;
      balas[b].terminada = true;
      balas[b].resultado = res;
      if(res == "SL")      balasConSL++;
      else if(res == "BE") balasConBE++;
      else if(res == "SP") balasConSP++;
      else if(res == "TP") balasConTP++;
   }

   balaActual = maxBala;

   if(balaActual > 0)
   {
      Print("[RECUPERACION] Estado reconstruido desde historial:");
      Print(" Balas lanzadas hoy : ", balaActual);
      Print(" Resultados         : TP:", balasConTP, " SP:", balasConSP,
            " BE:", balasConBE, " SL:", balasConSL);
      Print(" Bala en curso      : ", balaEnCurso ? "SI (B" + IntegerToString(balaActual) + ")" : "NO");
   }
}

//+------------------------------------------------------------------+
//| HISTORIAL: helpers de identificacion de deals (v2.66)            |
//| Todos usan la seleccion de historial ACTIVA (HistorySelect).     |
//+------------------------------------------------------------------+

// Numero de bala (1-8) contenido en un comentario "..._B3_BUY_E1", 0 si ninguno
int NumeroBalaDeComentario(string cmt)
{
   for(int b = 1; b <= 8; b++)
      if(StringFind(cmt, "_B" + IntegerToString(b) + "_") >= 0) return b;
   return 0;
}

// Comentario y precio del deal de ENTRADA de una posicion
bool DatosEntradaPosicion(long positionId, string &comentario, double &precio)
{
   int total = HistoryDealsTotal();
   for(int j = 0; j < total; j++)
   {
      ulong t = HistoryDealGetTicket(j);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(t, DEAL_ENTRY)       != DEAL_ENTRY_IN) continue;
      comentario = HistoryDealGetString(t, DEAL_COMMENT);
      precio     = HistoryDealGetDouble(t, DEAL_PRICE);
      return true;
   }
   return false;
}

// Tag del EA para un deal de SALIDA: el comentario de su deal de entrada.
// Si no se encuentra la entrada, se usa el comentario del propio deal.
string TagDealSalida(ulong ticket, double &precioEntrada)
{
   string cmt = "";
   precioEntrada = 0;
   long pid = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   if(DatosEntradaPosicion(pid, cmt, precioEntrada) && cmt != "")
      return cmt;
   return HistoryDealGetString(ticket, DEAL_COMMENT);
}

// Tolerancia (pips) para considerar un cierre como Break Even
double ToleranciaBEPips()
{
   return MathMax(0.5, 0.2 * MathMin(StopLossPips, CP1Pips));
}

// Clasificar un deal de salida: "TP", "SL", "BE", "SP" o "MANUAL".
// Compara precio de salida con precio de entrada (no profit == 0), con tolerancia.
string ClasificarDealSalida(ulong ticket, double precioEntrada)
{
   long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
   if(reason == DEAL_REASON_TP) return "TP";

   int signo = 0; // +1 ganancia, -1 perdida, 0 break even
   if(precioEntrada > 0 && pipSize > 0)
   {
      double precioSalida = HistoryDealGetDouble(ticket, DEAL_PRICE);
      // El deal de salida de una compra es DEAL_TYPE_SELL y viceversa
      bool   eraCompra    = (HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_SELL);
      double resPips      = eraCompra ? (precioSalida - precioEntrada) / pipSize
                                      : (precioEntrada - precioSalida) / pipSize;
      double tol          = ToleranciaBEPips();
      signo = (resPips > tol) ? 1 : ((resPips < -tol) ? -1 : 0);
   }
   else
   {
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      signo = (profit > 0) ? 1 : ((profit < 0) ? -1 : 0);
   }

   if(reason == DEAL_REASON_SL || reason == DEAL_REASON_SO)
      return (signo > 0) ? "SP" : ((signo < 0) ? "SL" : "BE");
   if(reason == DEAL_REASON_EXPERT) // TP1 cerrado por el EA o cierre diario
      return (signo > 0) ? "TP" : ((signo < 0) ? "SL" : "BE");
   return "MANUAL";
}

//+------------------------------------------------------------------+
//| PnL NETO DEL DIA EN %                                            |
//| Positivo = ganancia, Negativo = perdida                          |
//+------------------------------------------------------------------+
double GetPnLNetoDiarioPct(bool forzar = false)
{
   if(balanceInicioDia <= 0) return 0;

   // Usar cache si ya se calculo en este minuto (salvo forzar refresco)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   if(!forzar && nowMin == cachePnLMin) return cachePnLPct;

   // Solo deals cerrados — NO incluir flotante para evitar que posiciones
   // abiertas distorsionen el PnL del dia y los contadores de TP/SL.
   // v2.66: solo los deals de ESTE EA (magic + simbolo). Antes se usaba
   // balance - balanceInicioDia, que incluia otros EAs, depositos y retiros.
   double pnlNeto = PnLCerradoDiaUSD();

   cachePnLPct = (pnlNeto / balanceInicioDia) * 100.0;
   cachePnLMin = nowMin;
   return cachePnLPct;
}

//+------------------------------------------------------------------+
//| TOTAL DE BALAS MAXIMAS HOY (DINAMICO)                            |
//| Se recalcula en tiempo real segun el presupuesto restante        |
//| Si las balas ganan, el presupuesto crece y el techo sube         |
//| Techo absoluto: 8 balas                                          |
//+------------------------------------------------------------------+
int GetTotalBalasMax()
{
   if(RiskPerBala <= 0) return 0;
   double presup   = GetPresupuestoRestantePct();
   int    lanzadas = ContarBalasHoy();
   // Balas que el presupuesto restante permite + las ya lanzadas
   int total = (int)(presup / RiskPerBala) + lanzadas;
   return MathMin(8, MathMax(0, total));
}

//+------------------------------------------------------------------+
//| BALAS FISICAS RESTANTES HOY                                      |
//| Descuenta toda bala lanzada, ganadora o perdedora                |
//+------------------------------------------------------------------+
int GetBalasRestantes()
{
   int lanzadas = ContarBalasHoy();
   int restantes = GetTotalBalasMax() - lanzadas;
   return MathMax(0, restantes);
}

//+------------------------------------------------------------------+
//| PRESUPUESTO DE RIESGO RESTANTE (%)                               |
//| Solo mide perdidas reales realizadas                             |
//+------------------------------------------------------------------+
double GetPresupuestoRestantePct()
{
   // v2.66: PnL del dia solo de este EA (ver GetPnLNetoDiarioPct)
   double pnlNeto = GetPnLNetoDiarioPct();

   // Solo perdidas — si el dia es positivo el presupuesto esta intacto
   double perdidaPct = (pnlNeto < 0) ? MathAbs(pnlNeto) : 0;
   // Reserva opcional para cubrir el deslizamiento del SL de la ultima bala
   double restante   = MaxDailyLossPct - perdidaPct - MathMax(0, ReservaDeslizamientoPct);
   return MathMax(0, restante);
}

//+------------------------------------------------------------------+
//| PnL CERRADO DEL DIA EN DIVISA — SOLO DEALS DE ESTE EA (v2.66)    |
//| Incluye beneficio, swap, comision (tambien la de entrada) y fee. |
//| Excluye depositos, retiros y operaciones de otros EAs.           |
//+------------------------------------------------------------------+
double PnLCerradoDiaUSD()
{
   datetime desde = inicioDiaOperativo;
   if(desde <= 0)
   {
      datetime ahora = TimeCurrent();
      MqlDateTime dtA;
      TimeToStruct(ahora, dtA);
      desde = ahora - dtA.hour * 3600 - dtA.min * 60 - dtA.sec;
   }
   if(!HistorySelect(desde, TimeCurrent() + 86400)) return 0;

   double pnl   = 0;
   int    total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != MagicNumber) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)     continue;
      long tipo = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(tipo != DEAL_TYPE_BUY && tipo != DEAL_TYPE_SELL) continue;
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
           + HistoryDealGetDouble(ticket, DEAL_SWAP)
           + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
           + HistoryDealGetDouble(ticket, DEAL_FEE);
   }
   return pnl;
}

//+------------------------------------------------------------------+
//| PUEDE LANZAR UNA NUEVA BALA?                                     |
//| Requiere balas fisicas restantes Y presupuesto de riesgo         |
//+------------------------------------------------------------------+
bool PuedeLanzarBala()
{
   if(GetBalasRestantes()       <= 0) return false;
   if(GetPresupuestoRestantePct() <= 0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| COMPATIBILIDAD — usado en checks de limite diario                |
//+------------------------------------------------------------------+
int GetBalasDisponibles()
{
   return GetBalasRestantes();
}

//+------------------------------------------------------------------+
//| INICIALIZACION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   // v2.66: modo de llenado segun el simbolo (CTrade usa FOK por defecto y
   // muchos brokers de indices solo aceptan IOC/Return → error 10030)
   if(!trade.SetTypeFillingBySymbol(_Symbol))
      Print("AVISO: no se pudo determinar el modo de llenado del simbolo; se usa el de CTrade.");

   // v2.66: la logica de 2 entradas (E1/E2) con SL/TP propios exige cuenta HEDGING.
   // En netting E1 y E2 se fusionan en una sola posicion con un unico SL/TP.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("ERROR: London_Breakout requiere una cuenta HEDGING. ",
            "Esta cuenta es NETTING/EXCHANGE: el EA no se iniciara.");
      return INIT_FAILED;
   }

   symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // pipSize = valor de 1 pip en precio
   // Se calcula como _Point * PuntosPerPip
   // Ejemplo broker con Digitos=2, _Point=0.01, PuntosPerPip=100:
   //   pipSize = 0.01 * 100 = 1.00  → 50 pips = 50 puntos de precio [OK]
   // Ejemplo broker con Digitos=0, _Point=1, PuntosPerPip=1:
   //   pipSize = 1 * 1 = 1.00       → igual resultado [OK]
   pipSize = _Point * PuntosPerPip;
   if(pipSize <= 0) pipSize = _Point;

   RecalcHours();
   SyncDashParams();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   // Cachear datos del simbolo que no cambian durante la sesion
   symMinLot      = MathMax(LoteMinBroker, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   symMaxLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   symLotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   // v2.66: usar SIEMPRE el paso del broker (antes se forzaba a LoteMinBroker,
   // lo que generaba volumenes invalidos con paso 0.1)
   if(symLotStep <= 0) symLotStep = 0.01;
   for(int i = 0; i < 8; i++)
   {
      balas[i].id        = i + 1;
      balas[i].direction = 0;
      balas[i].active    = false;
      balas[i].e2Abierta = false;
      balas[i].cp1Done   = false;
      balas[i].tp1Done   = false;
      balas[i].cp3Done   = false;
      balas[i].tp2Done   = false;
      balas[i].terminada = false;
      balas[i].resultado = "NA";
   }

   balanceInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   MqlDateTime dtInit;
   TimeToStruct(TimeCurrent(), dtInit);
   // Dia operativo: desde la medianoche broker (no hay operativa entre el reset y medianoche)
   inicioDiaOperativo = TimeCurrent() - dtInit.hour * 3600 - dtInit.min * 60 - dtInit.sec;
   currentDay = dtInit.day;

   // Si el EA arranca despues de la ventana de Londres,
   // calcular el rango retroactivamente desde el historial
   int nowMinInit = dtInit.hour * 60 + dtInit.min;
   int londonEndMin = londonEndH * 60 + londonEndM;
   if(nowMinInit > londonEndMin)
   {
      if(UpdateRange(londonStartH * 60 + londonStartM, londonEndMin))
      {
         rangeFijado = true;
         londresIniciadoAlertado = true; // suprimir alerta de inicio (ya paso)
         RangoDisbujar();
         VLinDisbujar();
         Print(" Rango reconstruido retroactivamente: ",
               DoubleToString((rangeHigh-rangeLow)/pipSize, 1), " pips",
               " | Alto:", rangeHigh, " Bajo:", rangeLow);
         // No se envia Telegram al reconstruir el rango retroactivamente
         // El mensaje solo se envia en tiempo real al cierre de la sesion de Londres
      }
      else
         Print(" ADVERTENCIA: No se pudo reconstruir el rango de Londres. Se reintentara en OnTick.");
   }

   // Si el EA arranca en un dia diferente al ultimo registrado (ej. lunes tras
   // fin de semana donde el reset del viernes no se ejecuto por falta de ticks),
   // ejecutar ResetDaily() antes de recuperar el estado para que el nuevo dia
   // arranque con contadores limpios.
   MqlDateTime dtOnInit;
   TimeToStruct(TimeCurrent(), dtOnInit);
   if(currentDay != 0 && dtOnInit.day != currentDay)
   {
      Print("OnInit: nuevo dia detectado (", currentDay, " → ", dtOnInit.day, ") — ejecutando reset diario");
      ResetDaily();
      resetEjecutado = true;
   }
   currentDay = dtOnInit.day;

   // Recuperar estado si el EA se reinicio en mitad del dia
   RecuperarEstadoDesdHistorial();

   // Verificar si hay ordenes pendientes o posiciones activas del EA
   // (caso: reinicio por cambio de temporalidad con bala ya lanzada)
   if(HayOrdenesOPosicionesActivas())
   {
      balaEnCurso = true;
      if(balaActual == 0) balaActual = 1; // al menos 1 bala en curso

      // FIX: marcar balas[idx].active = true para cada bala con posiciones/ordenes
      // RecuperarEstadoDesdHistorial solo marca active si hay deals de SALIDA,
      // pero una bala recien activada solo tiene deals de ENTRADA, por lo que
      // balas[idx].active queda en false y ManageCheckpointsBala retorna sin hacer nada
      for(int b = 0; b < 8; b++)
      {
         string tagB = TradeComment + "_B" + IntegerToString(b+1);
         bool balaTienePos = false;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!posInfo.SelectByIndex(i)) continue;
            if(posInfo.Magic()  != MagicNumber) continue;
            if(posInfo.Symbol() != _Symbol)     continue;
            if(StringFind(posInfo.Comment(), tagB) >= 0) { balaTienePos = true; break; }
         }
         if(!balaTienePos)
         {
            for(int i = OrdersTotal() - 1; i >= 0; i--)
            {
               ulong ticket = OrderGetTicket(i);
               if(ticket == 0) continue;
               if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
               if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
               if(StringFind(OrderGetString(ORDER_COMMENT), tagB) >= 0) { balaTienePos = true; break; }
            }
         }
         if(balaTienePos)
         {
            balas[b].active    = true;
            balas[b].terminada = false;
            Print(" Bala ", b+1, " marcada active=true (posiciones/ordenes detectadas)");
         }
      }
      Print(" Ordenes/posiciones activas detectadas — bala en curso recuperada.");
   }

   Print("============================================");
   Print(" London_Breakout_v2.66 - SISTEMA DE BALAS");
   Print("--------------------------------------------");
   Print(" Broker GMT offset  : GMT+", brokerOffsetHours,
         " | Londres: GMT+", GetGMTLondres(),
         " | NY: GMT", GetGMTNY());
   Print(" Modo DST           : ", UsarDSTAutomatico ? "AUTOMATICO" : "MANUAL");
   Print(" Rango Londres      : ", londonStartH, ":00 - ", londonEndH, ":59 (broker)");
   Print(" Ventana NY         : ", nyOpenH, ":00 - ", cancelH, ":00 (NY Open + 4h)");
   Print(" Cierre mercado NY  : ", closeAllH, ":00 (broker)");
   Print("--------------------------------------------");
   Print(" Riesgo por bala    : ", RiskPerBala, "% (", RiskPerBala/2, "% por entrada)");
   Print(" Limite perdida/dia : ", MaxDailyLossPct, "%");
   Print(" SL / TP1 / TP2     : ", StopLossPips, " / ", TP1Pips, " / ", TP2Pips, " pips");
   Print(" pipSize (tick)     : ", DoubleToString(pipSize, symDigits+1),
         " | _Point: ", DoubleToString(_Point, symDigits+1),
         " | Stops minimo: ", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), " pts");
   Print(" SL en precio       : ", DoubleToString(StopLossPips * pipSize, symDigits));
   Print(" ContractSize       : ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   Print(" TickValue          : ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
   Print(" TickSize           : ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
   Print(" LoteMinimo         : ", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
         " (broker) | ", DoubleToString(LoteMinBroker,2), " (parametro)");
   Print(" ValorPuntoPorLote  : $", DoubleToString(ValorPuntoPorLote,2), " por pip por lote (solo respaldo)");
   double slEjemplo  = StopLossPips * pipSize;
   double lotEjemplo = CalculateLots(slEjemplo, RiskPerBala / 2.0);
   double riesgoReal = PerdidaPorLote(slEjemplo) * lotEjemplo;
   Print(" Lote ejemplo (", DoubleToString(RiskPerBala/2,1), "% / SL=", StopLossPips, "p): ",
         DoubleToString(lotEjemplo,2), " lotes | Riesgo real: $", DoubleToString(riesgoReal,2));
   Print(" Trailing CP3       : ", UseTrailingCP3 ? "SI" : "NO");
   Print("--------------------------------------------");
   Print(" Balance inicio dia : $", DoubleToString(balanceInicioDia, 2));
   Print(" Balas lanzadas hoy : ", balaActual, " | TP:", balasConTP, " SP:", balasConSP, " BE:", balasConBE, " SL:", balasConSL);
   Print("============================================");

   // v2.66: temporizador para vaciar la cola de Telegram fuera de OnTick
   if(!EventSetTimer(1))
      Print("AVISO: no se pudo crear el temporizador (Telegram no se enviara). Error ", GetLastError());

   if(!reinicioTemporal)
      TelegramBotIniciado();
   reinicioTemporal = false;

   // Si el EA arranca durante la ventana NY y el rango ya esta fijado → dibujar niveles
   if(rangeFijado && NivelesVisible)
   {
      MqlDateTime dtNow;
      TimeToStruct(TimeCurrent(), dtNow);
      int nowM = dtNow.hour * 60 + dtNow.min;
      int nyO  = nyOpenH * 60;
      int canc = cancelH * 60;
      if(canc <= nyO) canc += 1440;
      int nowAdj = (canc > 1440 && nowM < nyO) ? nowM + 1440 : nowM;
      if(nowAdj >= nyO && nowAdj < canc)
      {
         double entryBuy  = PrecioEntradaBuy();
         double entrySell = PrecioEntradaSell();
         double slDist    = StopLossPips * pipSize;
         double tp1Dist   = TP1Pips     * pipSize;
         double tp2Dist   = TP2Pips     * pipSize;
         NivelesDisbujar(0,
            entryBuy,  entrySell,
            entryBuy  - slDist,  entrySell + slDist,
            entryBuy  + tp1Dist, entrySell - tp1Dist,
            entryBuy  + tp2Dist, entrySell - tp2Dist);
         nivelesNYDibujados = true;
         VLinDisbujar();
      }
   }

   PanelUpdate();
   CSVInit();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DESINICIALIZACION                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Motivos de deinit que NO deben cancelar ordenes ni cerrar posiciones:
   // REASON_CHARTCHANGE  = 3  → cambio de temporalidad
   // REASON_PARAMETERS   = 5  → cambio de parametros
   // REASON_RECOMPILE    = 4  → recompilacion
   // REASON_CHARTCLOSE   = 6  → grafico cerrado (MT5 lo reabre)
   // REASON_TEMPLATE     = 7  → cambio de template
   // REASON_INITFAILED   = 8  → fallo en OnInit (no habia ordenes aun)
   // REASON_CLOSE        = 9  → cierre de MT5 (podria mantenerse)

   bool esCambioTemporal = (reason == REASON_CHARTCHANGE ||
                            reason == REASON_PARAMETERS  ||
                            reason == REASON_RECOMPILE   ||
                            reason == REASON_TEMPLATE);

   EventKillTimer();

   // Solo eliminar panel y niveles siempre (se reconstruyen en OnInit)
   PanelDestroy();
   RangoEliminar();
   NivelesEliminarTodo();
   VLinEliminar();

   if(esCambioTemporal)
   {
      reinicioTemporal = true;
      Print("London_Breakout_v2.66 reiniciando (razon ", reason, ") — ordenes preservadas.");
      return;
   }

   // Detencion real: cancelar ordenes, guardar CSV y notificar
   CSVGuardarDia();
   CancelPendingOrders();
   TelegramBotDetenido("Codigo " + IntegerToString(reason));
   TelegramProcesarCola(10); // vaciar la cola antes de salir (sin OnTimer ya)
   Print("London_Breakout_v2.66 detenido. Razon: ", reason);
}

//+------------------------------------------------------------------+
//| TICK PRINCIPAL                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int nowMin = dt.hour * 60 + dt.min;

   // Cambio de dia del calendario: recalcular horas DST y habilitar nuevo reset
   if(dt.day != currentDay)
   {
      RecalcHours();
      resetEjecutado = false; // habilitar reset para el nuevo dia
      currentDay     = dt.day;
   }

   int londonStart = londonStartH * 60 + londonStartM;
   int londonEnd   = londonEndH   * 60 + londonEndM;
   int nyOpen      = nyOpenH      * 60;
   int cancelTime  = cancelH      * 60;
   int closeTime   = closeAllH    * 60;

   // Los viernes reducir la ventana NY a VentanaViernesPips horas (default 3h)
   // para evitar rupturas falsas en cierre de semana
   if(dt.day_of_week == 5 && VentanaViernesPips < 4)
      cancelTime = nyOpen + VentanaViernesPips * 60;

   // Los viernes adelantar closeTime (CierreViernesBroker, por defecto 22:00 broker)
   // para que el reset se ejecute cuando aun hay ticks disponibles.
   // Si closeTime = 23:00 y el mercado cierra a 22:00, no llegan ticks
   // y el reset nunca ocurre — el lunes arranca con datos del viernes.
   if(dt.day_of_week == 5 && CierreViernesBroker >= 0)
      closeTime = CierreViernesBroker * 60;

   // Correccion para horas que cruzan medianoche (ej. GMT+3: cierre NY = 00:00)
   // Si closeTime es 0 o menor que nyOpen, significa que cae en el dia siguiente
   // En ese caso tratarlo como 24*60 = 1440 para comparaciones correctas
   if(closeTime <= nyOpen)  closeTime  += 1440;
   if(cancelTime <= nyOpen) cancelTime += 1440;
   // Ajustar nowMin si estamos en las horas de madrugada despues de medianoche
   int nowMinAdj = nowMin;
   if(closeTime > 1440 && nowMin < nyOpen) nowMinAdj = nowMin + 1440;

   // RESET DIARIO al cierre de NY (una sola vez por ciclo)
   if(nowMinAdj >= closeTime)
   {
      if(!resetEjecutado)
      {
         // Alerta cierre NY antes del reset
         if(!cierreNYAlertado)
         {
            double pnlNeto = GetPnLNetoDiarioPct();
            double pnlUSD  = balanceInicioDia * pnlNeto / 100.0;
            TelegramSend("🔔 <b>CIERRE SESIÓN NY</b>\n" +
               "----------------\n" +
               "Balas:    " + IntegerToString(balaActual) +
                  " (" + IntegerToString(balasConTP) + "TP " + IntegerToString(balasConSP) + "SP "
                  + IntegerToString(balasConBE) + "BE " + IntegerToString(balasConSL) + "SL)\n" +
               "PnL día:  " + (pnlNeto >= 0 ? "+" : "") + DoubleToString(pnlNeto, 2) + "%" +
                  " (" + (pnlUSD >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(pnlUSD), 2) + ")\n" +
               "Balance:  $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
               "----------------\n" +
               "✅ Reset diario ejecutado.");
            cierreNYAlertado = true;
         }
         CloseAllPositions();
         CancelPendingOrders();
         ResetDaily();
         resetEjecutado = true;
         cierreNYHecho  = true;
      }
      if(dt.min != lastPanelMin) { PanelUpdate(); lastPanelMin = dt.min; }
      return;
   }

   // Gestion de la bala en curso (BE, SP, trailing) en CUALQUIER momento del dia.
   // v2.66: antes solo se gestionaba dentro de la ventana NY, por lo que entre
   // cancelTime y closeTime las posiciones abiertas quedaban sin BE ni trailing.
   if(balaEnCurso && balaActual > 0)
      ManageCheckpointsBala(balaActual - 1);

   if(!CanTradeToday(dt.day_of_week)) return;

   // Calcular rango de Londres en vivo (solo velas cerradas) — max 1 vez por minuto
   if(nowMin >= londonStart && nowMin <= londonEnd && !rangeFijado)
   {
      if(dt.min != lastRangeMin)
      {
         UpdateRange(londonStart, londonEnd);
         lastRangeMin = dt.min;
         rangoEnVivo  = true;
         RangoDisbujar();

         // Alerta inicio de sesion Londres — una sola vez
         if(!londresIniciadoAlertado)
         {
            TelegramSend("📊 <b>SESIÓN LONDRES INICIADA</b>\n" +
               "----------------\n" +
               "Londres:  " + IntegerToString(londonStartH) + ":00 - " + IntegerToString(londonEndH) + ":59\n" +
               "NY Open:  " + IntegerToString(nyOpenH) + ":00\n" +
               "Balance:  $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
            londresIniciadoAlertado = true;
         }
      }
      if(dt.min != lastPanelMin) { PanelUpdate(); lastPanelMin = dt.min; }
      return;
   }

   // v2.66: fijar el rango en el primer tick POSTERIOR a la sesion de Londres,
   // cuando la ultima vela M1 (londonEnd) ya esta cerrada. Antes se fijaba en el
   // minuto londonEnd con esa vela recien abierta. Si falla (historial M1 aun no
   // sincronizado) se reintenta en los ticks siguientes (max 1 vez por segundo).
   if(!rangeFijado && nowMin > londonEnd)
   {
      static datetime ultimoIntentoRango = 0;
      static datetime ultimoAvisoRango   = 0;
      if(TimeCurrent() != ultimoIntentoRango)
      {
         ultimoIntentoRango = TimeCurrent();
         if(UpdateRange(londonStart, londonEnd))
         {
            rangeFijado = true;
            Print("RANGO FIJADO: ", DoubleToString((rangeHigh-rangeLow)/pipSize,1),
                  " pips | Alto:", rangeHigh, " Bajo:", rangeLow);
            RangoDisbujar();
            VLinDisbujar();
            // Telegram solo si la sesion se siguio en vivo (no al reconstruir tras un reinicio)
            if(rangoEnVivo)
               TelegramSend("📐 <b>RANGO DE LONDRES FIJADO</b>\n" +
                  "----------------\n" +
                  "Alto:     " + DoubleToString(rangeHigh, symDigits) + "\n" +
                  "Bajo:     " + DoubleToString(rangeLow,  symDigits) + "\n" +
                  "Amplitud: " + DoubleToString((rangeHigh-rangeLow)/pipSize,1) + " pips\n" +
                  "NY Open:  " + IntegerToString(nyOpenH) + ":00 broker");
         }
         else if(TimeCurrent() - ultimoAvisoRango > 300)
         {
            Print("AVISO: no se pudo calcular el rango de Londres (historial M1 no disponible). Reintentando...");
            ultimoAvisoRango = TimeCurrent();
         }
      }
   }

   // Ventana NY — solo con el rango DEFINITIVO (v2.66: antes bastaba rangeSet)
   if(nowMinAdj >= nyOpen && nowMinAdj < cancelTime && rangeFijado)
   {
      // Dibujar niveles al inicio de NY — una sola vez por dia
      if(!nivelesNYDibujados && NivelesVisible)
      {
         double entryBuy  = PrecioEntradaBuy();
         double entrySell = PrecioEntradaSell();
         double slDist    = StopLossPips * pipSize;
         double tp1Dist   = TP1Pips     * pipSize;
         double tp2Dist   = TP2Pips     * pipSize;
         // Usar idx=0 como referencia visual — los niveles son identicos para todas las balas
         // ya que el rango no cambia durante la sesion
         NivelesDisbujar(0,
            entryBuy,  entrySell,
            entryBuy  - slDist,  entrySell + slDist,
            entryBuy  + tp1Dist, entrySell - tp1Dist,
            entryBuy  + tp2Dist, entrySell - tp2Dist);
         nivelesNYDibujados = true;
         VLinDisbujar();
      }

      // La gestion de la bala en curso se hace al principio de OnTick (v2.66)
      if(!balaEnCurso && !HayOrdenesOPosicionesActivas())
         TryLanzarBala();
   }

   // Al salir de la ventana NY: cancelar pendientes una sola vez
   if(nowMinAdj >= cancelTime && !cierreNYHecho)
   {
      CancelPendingOrders();
      cierreNYHecho = true;
   }

   // Panel: refrescar una vez por minuto (no en cada tick)
   if(dt.min != lastPanelMin)
   {
      PanelUpdate();
      lastPanelMin = dt.min;
   }
}

//+------------------------------------------------------------------+
//| VERIFICAR CONFIRMACION DE REINGRESO                              |
//| Se evalua en cada tick.                                          |
//| Busca N velas M1 CERRADAS consecutivas con cierre dentro rango  |
//+------------------------------------------------------------------+
bool ConfirmacionReingreso()
{
   // Si confirmacion desactivada → pasar directo
   if(!UsarConfirmacion || VelasConfirmacion <= 0) return true;

   // Si no estamos esperando confirmacion → pasar directo
   if(!esperandoConfirmacion) return true;

   // Rango debe estar definido
   if(!rangeSet || rangeHigh <= 0 || rangeLow <= 0) return false;

   // Obtener las ultimas velas M1 cerradas
   // offset=1 excluye la vela en formacion, tomamos suficientes para buscar consecutivas
   MqlRates velas[];
   // Buffer ampliado a +30 para cubrir casos donde el precio estuvo fuera
   // del rango por mas de 10 minutos antes de regresar
   int copiadas = CopyRates(_Symbol, PERIOD_M1, 1, VelasConfirmacion + 30, velas);
   if(copiadas <= 0) return false;

   // v2.66: contar desde la vela cerrada MAS RECIENTE hacia atras.
   // Antes se recorria de la mas antigua a la mas reciente y se aceptaba la
   // PRIMERA racha de N velas aunque las posteriores ya estuvieran fuera del rango.
   // CopyRates retorna [0]=mas antigua, [n-1]=mas reciente
   int consecutivas = 0;
   for(int i = copiadas - 1; i >= 0; i--)
   {
      // Velas anteriores al fin de la bala no cuentan
      if(velas[i].time <= ultimaVelaContada) break;

      double cierre = velas[i].close;
      if(cierre < rangeLow || cierre > rangeHigh) break; // la racha se corta

      consecutivas++;
      if(consecutivas >= VelasConfirmacion) break;
   }

   if(consecutivas >= VelasConfirmacion)
   {
      // Confirmacion alcanzada con las N velas cerradas mas recientes
      ultimaVelaContada     = velas[copiadas - 1].time;
      velasConfirmadas      = consecutivas;
      esperandoConfirmacion = false;
      Print("CONFIRMACION REINGRESO: ", consecutivas, "/", VelasConfirmacion,
            " velas M1 cerradas dentro del rango. Bala disponible.");
      return true;
   }

   // Log periodico cada minuto para no saturar
   static datetime ultimoLogConf = 0;
   if(TimeCurrent() - ultimoLogConf > 60)
   {
      Print("Confirmacion: ", consecutivas, "/", VelasConfirmacion,
            " velas M1 dentro del rango [",
            DoubleToString(rangeLow,symDigits), " - ",
            DoubleToString(rangeHigh,symDigits), "]");
      ultimoLogConf = TimeCurrent();
   }

   return false;
}

//+------------------------------------------------------------------+
//| VERIFICAR SI HAY ORDENES PENDIENTES O POSICIONES ACTIVAS DEL EA  |
//| Evita lanzar una nueva bala mientras la anterior sigue viva      |
//+------------------------------------------------------------------+
bool HayOrdenesOPosicionesActivas()
{
   // Verificar ordenes pendientes
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      return true; // Hay al menos una orden pendiente activa
   }

   // Verificar posiciones abiertas
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)     continue;
      return true; // Hay al menos una posicion abierta
   }

   return false;
}

//+------------------------------------------------------------------+
//| INTENTAR LANZAR UNA NUEVA BALA                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CONTAR BALAS REALES DEL DIA DESDE EL HISTORIAL                  |
//| Cuenta cuantos grupos de tags _B1_ _B2_ etc tuvieron al menos   |
//| un deal de activacion hoy — independiente de balaActual         |
//+------------------------------------------------------------------+
int ContarBalasHoy()
{
   // Cache por minuto — evita multiples HistorySelect en el mismo tick
   MqlDateTime dtC;
   TimeToStruct(TimeCurrent(), dtC);
   int nowMinC = dtC.hour * 60 + dtC.min;
   if(nowMinC == cacheBalasHoyMin) return cacheBalasHoy;

   datetime ahora = TimeCurrent();
   MqlDateTime dtA;
   TimeToStruct(ahora, dtA);
   datetime hoy    = ahora - dtA.hour*3600 - dtA.min*60 - dtA.sec;
   datetime manana = hoy + 86400;

   if(!HistorySelect(hoy, manana)) return balaActual;

   bool vistas[8] = {false, false, false, false, false, false, false, false};
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != MagicNumber) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)     continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_IN) continue;

      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      for(int b = 0; b < 8; b++)
      {
         if(StringFind(comment, "_B"+IntegerToString(b+1)+"_") >= 0)
         {
            vistas[b] = true;
            break;
         }
      }
   }

   int conteo = 0;
   for(int b = 0; b < 8; b++)
      if(vistas[b]) conteo++;

   // Si balaEnCurso y la bala activa aun no tiene deals, contarla igual
   if(balaEnCurso && balaActual > 0 && balaActual <= 8)
      if(!vistas[balaActual-1]) conteo++;

   int resultado = MathMax(conteo, balaActual); // nunca menor que balaActual
   cacheBalasHoy    = resultado;
   cacheBalasHoyMin = nowMinC;
   return resultado;
}

void TryLanzarBala()
{
   // Bot pausado manualmente — no lanzar nuevas balas
   if(botPausado) return;

   // Criterio de parada: ganancia diaria maxima alcanzada
   double perdidaNeta = GetPnLNetoDiarioPct();
   if(MaxDailyProfitPct > 0 && perdidaNeta >= MaxDailyProfitPct)
   {
      static datetime ultimoAvisoTP = 0;
      if(TimeCurrent() - ultimoAvisoTP > 300)
      {
         Print("TP DIARIO: ganancia neta = ", DoubleToString(perdidaNeta,2),
               "% >= ", MaxDailyProfitPct, "%. Sin mas balas hoy.");
         ultimoAvisoTP = TimeCurrent();
      }
      if(!tpDiarioAlcanzado)
      {
         CancelPendingOrders();
         double pnlUSD = balanceInicioDia * perdidaNeta / 100.0;
         TelegramSend("🎯 <b>OBJETIVO DIARIO ALCANZADO</b>\n" +
            "----------------\n" +
            "Ganancia:  +" + DoubleToString(perdidaNeta, 2) + "%" +
               " (+$" + DoubleToString(MathAbs(pnlUSD), 2) + ")\n" +
            "Balas:     " + IntegerToString(balaActual) +
               " (" + IntegerToString(balasConTP) + "TP " + IntegerToString(balasConSP) + "SP "
               + IntegerToString(balasConBE) + "BE " + IntegerToString(balasConSL) + "SL)\n" +
            "Balance:   $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
            "ℹ️ Posiciones abiertas siguen activas.");
         tpDiarioAlcanzado = true;
      }
      return;
   }

   // Criterio de parada: balas fisicas agotadas o presupuesto de riesgo agotado
   if(!PuedeLanzarBala())
   {
      static datetime ultimoAvisoMax = 0;
      if(TimeCurrent() - ultimoAvisoMax > 300)
      {
         int restantes   = GetBalasRestantes();
         double presup   = GetPresupuestoRestantePct();
         if(restantes <= 0)
            Print("BALAS AGOTADAS: ", ContarBalasHoy(), "/", GetTotalBalasMax(),
                  " balas lanzadas hoy. Sin mas balas.");
         else
            Print("PRESUPUESTO AGOTADO: ", DoubleToString(MaxDailyLossPct - presup, 2),
                  "% de ", DoubleToString(MaxDailyLossPct, 1), "% consumido. Sin mas balas.");
         ultimoAvisoMax = TimeCurrent();
      }
      if(!limiteDiarioAlertado && GetPresupuestoRestantePct() <= 0)
      {
         TelegramLimiteDiario(perdidaNeta, balasConSL, balasConTP);
         limiteDiarioAlertado = true;
      }
      return;
   }

   // Verificar que el precio este DENTRO del rango antes de lanzar
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= rangeLow || bid >= rangeHigh)
   {
      precioFueraRango = true;
      static datetime ultimoAvisoRango = 0;
      if(TimeCurrent() - ultimoAvisoRango > 60)
      {
         Print("Esperando que el precio regrese al rango [",
               DoubleToString(rangeLow,symDigits), " - ",
               DoubleToString(rangeHigh,symDigits), "] | Precio actual: ",
               DoubleToString(bid,symDigits));
         ultimoAvisoRango = TimeCurrent();
      }
      return;
   }

   // Precio acaba de regresar al rango — solo log interno, sin Telegram
   if(precioFueraRango)
   {
      precioFueraRango = false;
      Print("Precio regreso al rango. Iniciando confirmacion de reingreso.");
   }

   // Confirmacion de reingreso: N velas M1 cerradas dentro del rango
   if(!ConfirmacionReingreso()) return;

   LanzarBala(balaActual);
}

//+------------------------------------------------------------------+
//| PRECIOS DE ENTRADA (v2.66)                                       |
//+------------------------------------------------------------------+
// Normalizar un precio al tick size del simbolo (no solo a los digitos)
double NormalizarPrecio(double precio)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0) precio = MathRound(precio / ts) * ts;
   return NormalizeDouble(precio, symDigits);
}

// BuyStop: alto del rango + offset (+ spread actual si CompensarSpreadBuy)
double PrecioEntradaBuy()
{
   double offset = OffsetEntradaPips * pipSize;
   if(CompensarSpreadBuy)
      offset += MathMax(0, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   return NormalizarPrecio(rangeHigh + offset);
}

// SellStop: bajo del rango - offset (se ejecuta con el Bid: no necesita compensar spread)
double PrecioEntradaSell()
{
   return NormalizarPrecio(rangeLow - OffsetEntradaPips * pipSize);
}

//+------------------------------------------------------------------+
//| LANZAR UNA BALA                                                  |
//+------------------------------------------------------------------+
void LanzarBala(int idx)
{
   if(idx < 0 || idx > 7) return;
   if(!rangeSet || rangeHigh == 0 || rangeLow == 0) return;

   double rangePips = (rangeHigh - rangeLow) / pipSize;

   double halfRisk = RiskPerBala / 2.0;
   double slDist   = StopLossPips * pipSize;
   double tp1Dist  = TP1Pips      * pipSize;
   double tp2Dist  = TP2Pips      * pipSize;

   // Verificar nivel minimo de stops del broker y ajustar si es necesario
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * _Point; // stops level siempre en _Point
   if(stopsLevel > 0 && slDist < minDist)
   {
      Print("AVISO: SL (", DoubleToString(slDist/_Point,0),
            " pts) < minimo broker (", stopsLevel, " pts). Ajustando...");
      double factor = (minDist * 1.1) / slDist;
      slDist  *= factor;
      tp1Dist *= factor;
      tp2Dist *= factor;
      Print(" SL ajustado a: ", DoubleToString(slDist/_Point,0), " pts = ",
            DoubleToString(slDist/pipSize,1), " pips");
   }

   double lots = CalculateLots(slDist, halfRisk);
   if(lots <= 0)
   {
      static datetime ultimoAvisoLote = 0;
      if(TimeCurrent() - ultimoAvisoLote > 300)
      {
         Print("Lote no valido (0): bala ", idx+1, " no lanzada. Revisa riesgo, SL y lote minimo.");
         ultimoAvisoLote = TimeCurrent();
      }
      return;
   }

   // Validar spread — si es mayor que el SL la orden sera rechazada
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(spread >= slDist)
   {
      Print("AVISO: Spread (", DoubleToString(spread/pipSize,1), " pips) >= SL (",
            DoubleToString(StopLossPips,1), " pips). Bala ", idx+1, " no lanzada.");
      return;
   }

   // v2.66: filtro de spread maximo (opcional)
   if(MaxSpreadPips > 0 && spread > MaxSpreadPips * pipSize)
   {
      static datetime ultimoAvisoSpread = 0;
      if(TimeCurrent() - ultimoAvisoSpread > 60)
      {
         Print("Spread ", DoubleToString(spread/pipSize,1), " pips > maximo ",
               DoubleToString(MaxSpreadPips,1), " pips. Bala ", idx+1, " en espera.");
         ultimoAvisoSpread = TimeCurrent();
      }
      return;
   }

   double entryBuy  = PrecioEntradaBuy();
   double entrySell = PrecioEntradaSell();

   // v2.66: las stops deben quedar por encima del Ask / por debajo del Bid y a la
   // distancia minima del broker. Si no, el broker las rechaza y la bala se abortaba
   // (con alerta Telegram) en cada intento: ahora simplemente se espera.
   long   freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistPend = MathMax(_Point, MathMax(stopsLevel, freezeLevel) * _Point);
   if(entryBuy - ask < minDistPend || bid - entrySell < minDistPend)
   {
      static datetime ultimoAvisoDist = 0;
      if(TimeCurrent() - ultimoAvisoDist > 60)
      {
         Print("Precio demasiado cerca de la entrada (Ask ", DoubleToString(ask, symDigits),
               " / BuyStop ", DoubleToString(entryBuy, symDigits), " | Bid ", DoubleToString(bid, symDigits),
               " / SellStop ", DoubleToString(entrySell, symDigits), "). Bala ", idx+1, " en espera.");
         ultimoAvisoDist = TimeCurrent();
      }
      return;
   }

   // --- Niveles BUY ---
   double slBuy   = NormalizarPrecio(entryBuy - slDist);
   double tp1Buy  = NormalizarPrecio(entryBuy + tp1Dist);
   double tp2Buy  = NormalizarPrecio(entryBuy + tp2Dist);

   // --- Niveles SELL ---
   double slSell  = NormalizarPrecio(entrySell + slDist);
   double tp1Sell = NormalizarPrecio(entrySell - tp1Dist);
   double tp2Sell = NormalizarPrecio(entrySell - tp2Dist);

   string tag = TradeComment + "_B" + IntegerToString(idx+1);

   // Colocar las 4 ordenes con reintentos (hasta 3 intentos, 500ms entre cada uno)
   bool b1ok = false, b2ok = false, s1ok = false, s2ok = false;

   for(int intento = 1; intento <= 3; intento++)
   {
      if(!b1ok) { b1ok = trade.BuyStop(lots, entryBuy, _Symbol, slBuy, tp1Buy, ORDER_TIME_DAY, 0, tag+"_BUY_E1");
                  if(!b1ok) Print("BALA ", idx+1, " | BUY_E1 intento ", intento, " FALLO: ", trade.ResultRetcodeDescription()); }
      if(!b2ok) { b2ok = trade.BuyStop(lots, entryBuy, _Symbol, slBuy, tp2Buy, ORDER_TIME_DAY, 0, tag+"_BUY_E2");
                  if(!b2ok) Print("BALA ", idx+1, " | BUY_E2 intento ", intento, " FALLO: ", trade.ResultRetcodeDescription()); }
      if(!s1ok) { s1ok = trade.SellStop(lots, entrySell, _Symbol, slSell, tp1Sell, ORDER_TIME_DAY, 0, tag+"_SEL_E1");
                  if(!s1ok) Print("BALA ", idx+1, " | SEL_E1 intento ", intento, " FALLO: ", trade.ResultRetcodeDescription()); }
      if(!s2ok) { s2ok = trade.SellStop(lots, entrySell, _Symbol, slSell, tp2Sell, ORDER_TIME_DAY, 0, tag+"_SEL_E2");
                  if(!s2ok) Print("BALA ", idx+1, " | SEL_E2 intento ", intento, " FALLO: ", trade.ResultRetcodeDescription()); }

      if(b1ok && b2ok && s1ok && s2ok) break; // todas colocadas exitosamente

      if(intento < 3)
      {
         Print("BALA ", idx+1, " | Ordenes incompletas en intento ", intento, "/3. Reintentando en 500ms...");
         Sleep(500);
      }
   }

   int ordenesOk = (b1ok?1:0) + (b2ok?1:0) + (s1ok?1:0) + (s2ok?1:0);

   // Si despues de 3 intentos no se colocaron todas: cancelar las parciales y abortar
   if(ordenesOk < 4)
   {
      Print("BALA ", idx+1, " | ERROR: Solo ", ordenesOk, "/4 ordenes colocadas tras 3 intentos. Cancelando bala.");

      // Cancelar todas las ordenes parciales de esta bala
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
         if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0) continue;
         trade.OrderDelete(ticket);
      }

      // v2.66: si alguna orden se ejecuto antes de cancelarla, hay posiciones
      // abiertas de esta bala. Antes la bala se abortaba igualmente y esas
      // posiciones quedaban huerfanas (sin BE ni trailing) y bloqueaban nuevas balas.
      bool hayPosicionAbierta = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic()  != MagicNumber) continue;
         if(posInfo.Symbol() != _Symbol)     continue;
         if(StringFind(posInfo.Comment(), tag) < 0) continue;
         hayPosicionAbierta = true;
         break;
      }

      if(!hayPosicionAbierta)
      {
         // Activar confirmacion para reintentar en el proximo ciclo
         if(UsarConfirmacion && VelasConfirmacion > 0)
         {
            esperandoConfirmacion = true;
            velasConfirmadas      = 0;
            double precioActual   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            precioFueraRango      = (precioActual <= rangeLow || precioActual >= rangeHigh);
            MqlRates velaActual[];
            if(CopyRates(_Symbol, PERIOD_M1, 0, 1, velaActual) > 0)
               ultimaVelaContada = velaActual[0].time;
            else
               ultimaVelaContada = TimeCurrent() - 60;
         }

         TelegramSend("⚠️ <b>BALA " + IntegerToString(idx+1) + " ABORTADA</b>\n" +
            "----------------\n" +
            "Error al colocar ordenes tras 3 intentos.\n" +
            "Ordenes OK: " + IntegerToString(ordenesOk) + "/4\n" +
            "Se reintentara en el proximo ciclo.");
         return;
      }

      // Hay posiciones: la bala queda en curso y se gestiona con normalidad
      Print("BALA ", idx+1, " | Una orden se ejecuto antes de cancelar: la bala queda EN CURSO",
            " con las posiciones abiertas.");
      TelegramSend("⚠️ <b>BALA " + IntegerToString(idx+1) + " INCOMPLETA</b>\n" +
         "----------------\n" +
         "Solo " + IntegerToString(ordenesOk) + "/4 ordenes colocadas, pero una ya se ejecuto.\n" +
         "La bala sigue en curso con las posiciones abiertas.");
   }

   // Inicializar bala
   balas[idx].id        = idx + 1;
   balas[idx].direction = 0;
   balas[idx].active    = true;
   balas[idx].e2Abierta = true;  // E2 ya esta colocada como orden pendiente
   balas[idx].cp1Done   = false;
   balas[idx].tp1Done   = false;
   balas[idx].cp3Done   = false;
   balas[idx].tp2Done   = false;
   balas[idx].terminada = false;
   balas[idx].resultado = "NA";

   balaEnCurso = true;
   balaActual  = idx + 1;
   if(horaprimeraBala == 0) horaprimeraBala = TimeCurrent();

   double perdidaNeta = GetPnLNetoDiarioPct();
   double margen      = MaxDailyLossPct + perdidaNeta;
   // rangePips ya calculado al inicio de la funcion — reutilizar

   // Dibujar niveles BUY en el grafico (la direccion se ajustara cuando se active)
   // Dibujamos los niveles BUY por defecto; se actualizan en OnTradeTransaction
   // Dibujar tambien niveles SELL

   // Alerta Telegram al lanzar la bala
   TelegramBalaLanzada(idx+1, rangePips, 0, perdidaNeta, margen);

   Print("--- BALA ", idx+1, " LANZADA (4 ordenes pendientes) ---");
   Print(" Rango   : ", DoubleToString(rangePips,1), " pips | Alto:", rangeHigh, " Bajo:", rangeLow);
   Print(" BUY  E1 : entrada=", entryBuy,  " SL=", slBuy,  " TP1=", tp1Buy,  " (", TP1Pips, " pips)");
   Print(" BUY  E2 : entrada=", entryBuy,  " SL=", slBuy,  " TP2=", tp2Buy,  " (", TP2Pips, " pips)");
   Print(" SELL E1 : entrada=", entrySell, " SL=", slSell, " TP1=", tp1Sell, " (", TP1Pips, " pips)");
   Print(" SELL E2 : entrada=", entrySell, " SL=", slSell, " TP2=", tp2Sell, " (", TP2Pips, " pips)");
   Print(" Lotes/entrada: ", lots, " | Riesgo/entrada:", halfRisk, "% | Riesgo/bala:", RiskPerBala, "%");
   Print(" PnL dia : ", DoubleToString(perdidaNeta,2), "% | Margen: ", DoubleToString(margen,2), "% / -", MaxDailyLossPct, "%");
   Print(" Balas   : ", balaActual, "/", GetTotalBalasMax(), " hoy (TP:", balasConTP, " SP:", balasConSP, " BE:", balasConBE, " SL:", balasConSL, ")");
}

//+------------------------------------------------------------------+
//| ACTUALIZA EL RANGO DE LONDRES (filtrado por dia actual)          |
//| v2.66: copia las velas M1 por RANGO DE TIEMPO (antes 600 velas   |
//| fijas, insuficientes si el EA arranca tarde) y usa solo velas    |
//| CERRADAS (antes se descartaba la mas antigua y se incluia la que |
//| estaba en formacion). Devuelve true si el rango es valido.       |
//+------------------------------------------------------------------+
bool UpdateRange(int startMinutes, int endMinutes)
{
   // Medianoche del dia actual en hora del broker (aritmetica directa)
   datetime ahora = TimeCurrent();
   MqlDateTime dtAhora;
   TimeToStruct(ahora, dtAhora);
   datetime inicioDiaBroker = ahora
                              - dtAhora.hour   * 3600
                              - dtAhora.min    * 60
                              - dtAhora.sec;

   datetime tDesde = inicioDiaBroker + startMinutes * 60;
   datetime tHasta = inicioDiaBroker + endMinutes   * 60; // apertura de la ultima vela de Londres

   MqlRates rates[];
   int bars = CopyRates(_Symbol, PERIOD_M1, tDesde, tHasta, rates);
   if(bars <= 0) return false;

   double high  = 0, low = DBL_MAX;
   bool   found = false;

   for(int i = 0; i < bars; i++)
   {
      if(rates[i].time < tDesde || rates[i].time > tHasta) continue;
      // Solo velas CERRADAS: una vela M1 abierta en T termina en T+60
      if(rates[i].time + 60 > ahora) continue;

      if(rates[i].high > high) high = rates[i].high;
      if(rates[i].low  < low)  low  = rates[i].low;
      found = true;
   }

   if(found && high > 0 && low < DBL_MAX && high > low)
   {
      rangeHigh = high;
      rangeLow  = low;
      rangeSet  = true;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GESTION DE CHECKPOINTS DE UNA BALA                               |
//+------------------------------------------------------------------+
void ManageCheckpointsBala(int idx)
{
   if(idx < 0 || idx > 7) return;
   if(!balas[idx].active) return;

   double profit1Pips = 0, profit2Pips = 0;
   bool   pos1Active  = false, pos2Active = false;
   ulong  t1 = 0, t2 = 0;

   string tag  = "_B" + IntegerToString(idx+1);
   string tagE1_buy  = tag + "_BUY_E1";
   string tagE2_buy  = tag + "_BUY_E2";
   string tagE1_sel  = tag + "_SEL_E1";
   string tagE2_sel  = tag + "_SEL_E2";

   // v2.66: si la direccion aun no se conoce (p.ej. tras un reinicio), tomar la
   // de la PRIMERA posicion abierta de la bala (por hora de apertura)
   if(balas[idx].direction == 0)
   {
      ulong tPrimera = ULONG_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic()  != MagicNumber) continue;
         if(posInfo.Symbol() != _Symbol)     continue;
         if(StringFind(posInfo.Comment(), tag) < 0) continue;
         if(posInfo.TimeMsc() < tPrimera)
         {
            tPrimera = posInfo.TimeMsc();
            balas[idx].direction = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         }
      }
   }

   bool hayOpuesta = false; // posiciones de la bala en la direccion contraria (OCO fallido)

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)     continue;

      string cmt = posInfo.Comment();
      if(StringFind(cmt, tag) < 0) continue;

      // Ignorar (y avisar) posiciones de la direccion contraria: no se mezclan
      // con E1/E2 de la direccion activa. Conservan su propio SL/TP en el broker.
      int dirPos = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      if(balas[idx].direction != 0 && dirPos != balas[idx].direction)
      {
         hayOpuesta = true;
         continue;
      }

      double openPrice = posInfo.PriceOpen();
      double curPrice  = (posInfo.PositionType() == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pips = (posInfo.PositionType() == POSITION_TYPE_BUY)
                    ? (curPrice - openPrice) / pipSize
                    : (openPrice - curPrice) / pipSize;

      bool esE1 = (StringFind(cmt, tagE1_buy) >= 0 || StringFind(cmt, tagE1_sel) >= 0);
      bool esE2 = (StringFind(cmt, tagE2_buy) >= 0 || StringFind(cmt, tagE2_sel) >= 0);

      if(esE1) { t1 = posInfo.Ticket(); profit1Pips = pips; pos1Active = true;
                 balas[idx].direction = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1; }
      if(esE2) { t2 = posInfo.Ticket(); profit2Pips = pips; pos2Active = true; }
   }

   // v2.66: red de seguridad del OCO. Si OnTradeTransaction no llego a cancelar
   // las stops opuestas (reconexion, reinicio), se cancelan aqui en cada tick.
   if(balas[idx].direction != 0)
      CancelOrdenesOpuestas(TradeComment + tag, balas[idx].direction);

   if(hayOpuesta && opuestaAlertadaBala != idx + 1)
   {
      Print("BALA ", idx+1, " | ALERTA: hay posiciones abiertas en AMBAS direcciones. ",
            "Solo se gestiona la direccion ", balas[idx].direction == 1 ? "BUY" : "SELL",
            "; la contraria queda con su SL/TP del broker.");
      TelegramSend("⚠️ <b>BALA " + IntegerToString(idx+1) + " — AMBAS DIRECCIONES ABIERTAS</b>\n" +
         "----------------\n" +
         "El OCO no cancelo a tiempo las ordenes opuestas.\n" +
         "Se gestiona solo " + (balas[idx].direction == 1 ? "BUY" : "SELL") +
         "; revisa la posicion contraria.");
      opuestaAlertadaBala = idx + 1;
   }

   // Bala terminada: ninguna posicion activa
   // IMPORTANTE: verificar tambien que no haya ordenes pendientes activas
   // Si hay ordenes pendientes = bala lanzada pero aun no activada, NO ha terminado
   if(!pos1Active && !pos2Active && !hayOpuesta)
   {
      // Verificar si hay ordenes pendientes de esta bala aun activas
      bool hayOrdenesPendientes = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC)  != MagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL)  != _Symbol)     continue;
         if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0) continue;
         hayOrdenesPendientes = true;
         break;
      }

      // Si hay ordenes pendientes, la bala esta esperando activacion
      if(hayOrdenesPendientes) return;

      // No hay posiciones ni ordenes → bala realmente terminada
      balas[idx].active = false;
      balaEnCurso = false;

      double pnlActual = GetPnLNetoDiarioPct(true);

      // Detectar tipo de cierre de cada entrada individualmente
      string tipoE1 = DetectarCierreEntrada(idx, 1);
      string tipoE2 = DetectarCierreEntrada(idx, 2);

      // Si DetectarCierreEntrada retorna "" puede significar dos cosas:
      // a) La entrada se activo pero el deal no se encontro aun (timing) → usar contexto
      // b) La entrada nunca se activo (orden cancelada sin ejecutarse) → no notificar
      // Distinguimos por direction: si direction==0 la bala nunca se activo
      bool balaActivada = (balas[idx].direction != 0);

      if(tipoE1 == "")
      {
         if(!balaActivada) tipoE1 = "NA"; // nunca activada — no notificar
         else tipoE1 = balas[idx].tp1Done ? "TP" : "SL";
      }
      if(tipoE2 == "")
      {
         if(!balaActivada) tipoE2 = "NA";
         else tipoE2 = balas[idx].tp2Done ? "TP" : (balas[idx].tp1Done ? "SP" : "SL");
      }

      // Determinar resultado global de la bala a partir de tipoE1 y tipoE2
      // Prioridad: SL > BE > SP > TP > NA
      // Una bala con E1=TP y E2=BE se clasifica como SP (ganancia parcial)
      // Una bala con E1=SL y E2=BE se clasifica como SL (perdida real)
      bool huboPerdida = (tipoE1 == "SL" || tipoE2 == "SL");
      bool huboGanancia = (tipoE1 == "TP" || tipoE2 == "TP" ||
                           tipoE1 == "SP" || tipoE2 == "SP");
      bool soloBE = !huboPerdida && !huboGanancia && balaActivada &&
                   (tipoE1 == "BE" || tipoE2 == "BE" ||
                    tipoE1 == "NA" || tipoE2 == "NA");

      string resGlobal;
      if(!balaActivada)         resGlobal = "NA";
      else if(huboPerdida)      resGlobal = "SL";
      else if(soloBE)           resGlobal = "BE";
      else if(tipoE1=="SP" || tipoE2=="SP") resGlobal = "SP";
      else                      resGlobal = "TP";

      balas[idx].resultado = resGlobal;

      if(resGlobal == "SL")      balasConSL++;
      else if(resGlobal == "BE") balasConBE++;
      else if(resGlobal == "SP") balasConSP++;
      else if(resGlobal == "TP") balasConTP++;

      // Notificar E1 solo si se activo y no fue cerrada previamente por TP1
      if(tipoE1 != "NA" && !balas[idx].tp1Done)
      {
         double pipsE1 = (tipoE1=="TP") ? TP1Pips : 0;
         TelegramEntradaCerrada(balas[idx].id, 1, tipoE1, pipsE1, pnlActual);
      }

      // Notificar E2 solo si se activo y no fue cerrada previamente por TP2
      if(tipoE2 != "NA" && !balas[idx].tp2Done)
      {
         double pipsE2 = (tipoE2=="TP") ? TP2Pips : (tipoE2=="SP") ? CP3Pips : 0;
         TelegramEntradaCerrada(balas[idx].id, 2, tipoE2, pipsE2, pnlActual);
      }

      TelegramBalaTerminada(balas[idx].id, tipoE1, tipoE2, pnlActual);

      Print("--- BALA ", balas[idx].id, " CERRADA | E1:", tipoE1, " E2:", tipoE2, " ---");

      double perdidaNeta    = GetPnLNetoDiarioPct();
      double margenRestante = MaxDailyLossPct + perdidaNeta;

      Print(" PnL neto dia   : ", DoubleToString(perdidaNeta,2), "% | Limite: -", MaxDailyLossPct, "%");
      Print(" Margen restante: ", DoubleToString(margenRestante,2), "%");
      Print(" Balas hoy      : ", balaActual, " (TP:", balasConTP, " SP:", balasConSP, " BE:", balasConBE, " SL:", balasConSL, ")");

      if(perdidaNeta <= -MaxDailyLossPct)
         Print(" LIMITE DIARIO ALCANZADO. No mas balas hoy.");
      else if(!PuedeLanzarBala())
         Print(" BALAS/PRESUPUESTO AGOTADO. No mas balas hoy.");
      else
         Print(" Siguiente bala disponible. Balas restantes: ", GetBalasDisponibles());

      balas[idx].terminada = true;

      // Activar espera de confirmacion antes de la siguiente bala
      if(UsarConfirmacion && VelasConfirmacion > 0)
      {
         esperandoConfirmacion = true;
         velasConfirmadas      = 0;
         // Si el precio ya esta dentro del rango (ej. SL): solo esperar vela de confirmacion
         // Si el precio esta fuera del rango (ej. TP):     esperar reingreso + vela
         double precioActual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         precioFueraRango = (precioActual <= rangeLow || precioActual >= rangeHigh);
         // Marcar la vela M1 ACTUAL (en formacion) como punto de partida
         // Cualquier vela que cierre DESPUES de este momento contara
         MqlRates velaActual[];
         if(CopyRates(_Symbol, PERIOD_M1, 0, 1, velaActual) > 0)
            ultimaVelaContada = velaActual[0].time; // vela actual en formacion
         else
            ultimaVelaContada = TimeCurrent() - 60;
         Print("Confirmacion requerida: ", VelasConfirmacion,
               " vela(s) M1 | Precio ", precioFueraRango ? "FUERA del rango - esperando reingreso" : "DENTRO del rango - esperando cierre de vela");
      }
      return;
   }

   // --- RECUPERACION DE ESTADO POR CIERRE EXTERNO DE E1 ---
   // Si E1 ya no esta activa (cerrada por broker en TP automaticamente) pero
   // cp1Done o tp1Done no se marcaron aun, inferirlos desde el historial.
   // Esto ocurre cuando el broker cierra E1 en TP antes de que el EA lo procese,
   // o cuando el SL/TP fue modificado manualmente y el checkpoint quedo pendiente.
   if(!pos1Active && !balas[idx].tp1Done)
   {
      string cierrE1 = DetectarCierreEntrada(idx, 1);
      if(cierrE1 == "TP" || cierrE1 == "BE" || cierrE1 == "SP")
      {
         if(!balas[idx].cp1Done)
         {
            balas[idx].cp1Done = true;
            statCP1++;
            Print("BALA ", balas[idx].id, " | CP1 recuperado desde historial (E1 cerrada externamente)");
            TelegramCheckpoint(balas[idx].id, 1, "Break Even activado en ambas entradas", CP1Pips);
         }
         // Marcar tp1Done y mover SP de E2 si corresponde
         bool spOk = true;
         if(pos2Active) spOk = MoveStopToProfit(t2, CP1Pips);
         if(spOk || !pos2Active)
         {
            balas[idx].tp1Done = true;
            statTP1++;
            Print("BALA ", balas[idx].id, " | TP1 recuperado desde historial (E1 cerrada externamente)");
            TelegramEntradaCerrada(balas[idx].id, 1, "TP", TP1Pips, GetPnLNetoDiarioPct());
         }
      }
   }

   // refPips para checkpoints:
   // CP1 y TP1 usan profit1Pips (E1 debe alcanzar el nivel)
   // CP3 y TP2 usan profit2Pips cuando E2 esta activa (E2 es la que sigue corriendo)
   // Si solo hay una posicion activa, usar la que este disponible
   double refPipsE1 = pos1Active ? profit1Pips : profit2Pips;
   double refPipsE2 = pos2Active ? profit2Pips : profit1Pips;

   // CP1: Break Even ambas — cuando E1 alcanza CP1Pips
   // cp1Done solo se marca si MoveToBreakEvenOk logro ejecutar en todas las posiciones activas
   // Si falla (stops level, etc.) se reintenta en el siguiente tick
   if(!balas[idx].cp1Done && refPipsE1 >= CP1Pips)
   {
      bool beOk = true;
      if(pos1Active) { if(!MoveToBreakEvenOk(t1)) beOk = false; }
      if(pos2Active) { if(!MoveToBreakEvenOk(t2)) beOk = false; }
      // Si el precio ya paso TP1 (movimiento muy rapido), pos1Active puede ser false
      // porque el broker ya cerro E1. En ese caso el BE no es necesario pero si la notificacion.
      if(beOk || (!pos1Active && refPipsE1 >= TP1Pips))
      {
         balas[idx].cp1Done = true;
         statCP1++;
         Print("BALA ", balas[idx].id, " | CP1 +", CP1Pips, " pips | Break Even activado");
         TelegramCheckpoint(balas[idx].id, 1, "Break Even activado en ambas entradas", CP1Pips);
      }
   }

   // TP1: Cerrar E1, SP E2 a +CP1Pips — cuando E1 alcanza TP1Pips
   if(!balas[idx].tp1Done && balas[idx].cp1Done && refPipsE1 >= TP1Pips)
   {
      if(pos1Active) { trade.PositionClose(t1); pos1Active = false;
                       Print("BALA ", balas[idx].id, " | TP1 | Entrada 1 cerrada +", TP1Pips, " pips"); }
      // Solo marcar tp1Done si el SP de E2 se aplico correctamente
      // Si falla por stops level, reintenta en el siguiente tick
      bool spOk = true;
      if(pos2Active) spOk = MoveStopToProfit(t2, CP1Pips);
      if(spOk || !pos2Active)
      {
         balas[idx].tp1Done = true;
         statTP1++;
         TelegramEntradaCerrada(balas[idx].id, 1, "TP", TP1Pips, GetPnLNetoDiarioPct());
      }
   }

   // --- RECUPERACION DE ESTADO POR CIERRE EXTERNO DE E2 ---
   // Si E2 ya no esta activa pero cp3Done no se marco, inferir desde historial
   if(!pos2Active && balas[idx].tp1Done && !balas[idx].cp3Done)
   {
      string cierrE2 = DetectarCierreEntrada(idx, 2);
      if(cierrE2 == "TP" || cierrE2 == "SP")
      {
         balas[idx].cp3Done = true;
         Print("BALA ", balas[idx].id, " | CP3 recuperado desde historial (E2 cerrada externamente)");
      }
   }

   // CP3: SP E2 a (CP3Pips - CP1Pips) desde entrada, trailing — cuando E2 alcanza CP3Pips
   if(!balas[idx].cp3Done && balas[idx].tp1Done && refPipsE2 >= CP3Pips)
   {
      // Solo marcar cp3Done si el SP se aplico correctamente
      bool spOk = true;
      if(pos2Active)
      {
         spOk = MoveStopToProfit(t2, CP3Pips - CP1Pips);
         if(spOk && UseTrailingCP3)
            Print("BALA ", balas[idx].id, " | Trailing Stop activado: ", CP3_TrailingPips, " pips");
         // Si RemoveTP2atCP4=true: eliminar el TP2 ahora en CP3
         // Es el momento correcto — si se espera a TP2, el broker ya cerro la posicion
         if(spOk && RemoveTP2atCP4)
         {
            RemoveTakeProfit(t2);
            Print("BALA ", balas[idx].id, " | CP3 | TP2 eliminado — TS correra sin techo");
         }
      }
      if(spOk || !pos2Active)
      {
         balas[idx].cp3Done = true;
         statCP3++;
         Print("BALA ", balas[idx].id, " | CP3 +", CP3Pips, " pips | SP E2 -> +", CP3Pips-CP1Pips, " pips");
         string msgCP3 = "SP E2 a +" + DoubleToString(CP3Pips-CP1Pips,0) + " pips";
         if(UseTrailingCP3)  msgCP3 += " | Trailing ON";
         if(RemoveTP2atCP4)  msgCP3 += " | TP eliminado — TS libre";
         TelegramCheckpoint(balas[idx].id, 3, msgCP3, CP3Pips);
      }
   }

   // TP2 (+200 pips) — referencia informativa cuando RemoveTP2atCP4=false
   // Con RemoveTP2atCP4=true el TP ya fue eliminado en CP3, la posicion
   // solo cierra cuando el TS la alcance (no hay nivel fijo de cierre)
   if(!balas[idx].tp2Done && balas[idx].cp3Done && refPipsE2 >= TP2Pips)
   {
      if(!RemoveTP2atCP4)
      {
         // TP2 fijo — el broker cierra E2 automaticamente en +200 pips
         // pos2Active puede ser false si el broker ya la cerro antes del tick
         Print("BALA ", balas[idx].id, " | TP2 +", TP2Pips, " pips | E2 cerrada en TP");
         TelegramEntradaCerrada(balas[idx].id, 2, "TP", TP2Pips, GetPnLNetoDiarioPct());
      }
      else
      {
         // RemoveTP2atCP4=true: el precio paso +200 pips pero la posicion sigue abierta
         // El TS la cerrara cuando retroceda. Solo notificar el hito.
         Print("BALA ", balas[idx].id, " | TP2 +", TP2Pips, " pips superados | TS libre corriendo");
         TelegramCheckpoint(balas[idx].id, 4,
            "Precio supero TP2 | TS libre sin techo | Min: +" +
            DoubleToString(TP2Pips - CP3_TrailingPips, 0) + " pips", TP2Pips);
      }
      balas[idx].tp2Done = true;
      statTP2++;
   }

   // Trailing Stop desde CP3 — solo sobre E2
   if(balas[idx].cp3Done && UseTrailingCP3 && pos2Active && t2 != 0)
      ApplyTrailingStop(t2, CP3_TrailingPips);
}

//+------------------------------------------------------------------+
//| DETECTAR SI UNA BALA TERMINO EN SL LEYENDO DEALS         |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| TIPO DE CIERRE DE UNA ENTRADA                                    |
//+------------------------------------------------------------------+
// Retorna: "TP", "SL", "BE", "SP", "MANUAL", "" si no encontrado
string DetectarCierreEntrada(int idx, int entrada)
{
   // entrada: 1=E1, 2=E2
   string tag = "_B" + IntegerToString(idx+1) +
                (entrada == 1 ? "_BUY_E1" : "_BUY_E2");
   string tagS= "_B" + IntegerToString(idx+1) +
                (entrada == 1 ? "_SEL_E1" : "_SEL_E2");

   datetime ahora = TimeCurrent();
   MqlDateTime dtA;
   TimeToStruct(ahora, dtA);
   datetime hoy    = ahora - dtA.hour * 3600 - dtA.min * 60 - dtA.sec;
   datetime manana = hoy + 86400;

   if(!HistorySelect(hoy, manana)) return "";

   int totalDeals = HistoryDealsTotal();
   for(int i = totalDeals - 1; i >= 0; i--) // buscar el mas reciente
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)     continue;

      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      // v2.66: el tag esta en el deal de ENTRADA (el de salida lleva "[sl ...]")
      double precioEntrada = 0;
      string comment = TagDealSalida(ticket, precioEntrada);
      if(StringFind(comment, tag) < 0 && StringFind(comment, tagS) < 0) continue;

      return ClasificarDealSalida(ticket, precioEntrada);
   }
   return "";
}

// Mantener compatibilidad con codigo existente
bool DetectarSLEnBala(int idx)
{
   string r1 = DetectarCierreEntrada(idx, 1);
   string r2 = DetectarCierreEntrada(idx, 2);
   // Es perdida si alguna entrada cerro en SL real
   return (r1 == "SL" || r2 == "SL");
}

// Wrapper que retorna true si el BE fue aplicado exitosamente (o ya estaba aplicado)
bool MoveToBreakEvenOk(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return false;
   double openPrice = posInfo.PriceOpen();
   double newSL     = NormalizeDouble(openPrice, symDigits);
   double currentSL = posInfo.StopLoss();
   bool   isBuy     = (posInfo.PositionType() == POSITION_TYPE_BUY);

   // Ya esta en BE o mejor — no hace falta mover
   bool yaEnBE = (isBuy  && currentSL >= newSL && currentSL != 0) ||
                 (!isBuy && currentSL <= newSL && currentSL != 0);
   if(yaEnBE) return true;

   // Validar stops level, freeze level y lado del precio (v2.66)
   double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!ModificacionPermitida(isBuy, newSL, currentSL, posInfo.TakeProfit()))
      return false; // diferir al proximo tick

   bool ok = trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
   if(ok) Print("BE activado | ticket #", ticket, " | SL → ", DoubleToString(newSL, symDigits),
                " | tipo: ", isBuy ? "BUY" : "SELL");
   else   Print("BE ERROR    | ticket #", ticket, " | error: ", GetLastError(),
                " | tipo: ", isBuy ? "BUY" : "SELL",
                " | newSL: ", DoubleToString(newSL, symDigits),
                " | curPrice: ", DoubleToString(curPrice, symDigits));
   return ok;
}

//+------------------------------------------------------------------+
//| MOVER SL A BREAK EVEN                                            |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;
   double openPrice = posInfo.PriceOpen();
   double newSL     = NormalizeDouble(openPrice, symDigits);
   double currentSL = posInfo.StopLoss();

   bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);

   // Para BUY: mover si newSL es mayor que el SL actual, o si no hay SL (currentSL==0)
   // Para SELL: mover si newSL es menor que el SL actual, o si no hay SL (currentSL==0)
   bool shouldMove = (isBuy  && (currentSL == 0 || newSL > currentSL)) ||
                     (!isBuy && (currentSL == 0 || newSL < currentSL));

   if(!shouldMove) return;

   // Validar distancia minima al precio actual (stops level del broker)
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist   = stopsLvl * _Point;
   double curPrice  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double distSL    = MathAbs(curPrice - newSL);

   if(stopsLvl > 0 && distSL < minDist)
   {
      // El precio ya paso el BE — ajustar newSL al minimo permitido
      // para que el SL quede lo mas cerca posible al openPrice sin rechazar
      Print("BE AVISO  | ticket #", ticket,
            " | Dist SL (", DoubleToString(distSL/_Point,0),
            " pts) < stops level (", stopsLvl, " pts). BE diferido.");
      // No marcar cp1Done aqui — se reintentara en el proximo tick
      return;
   }

   bool ok = trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
   if(ok) Print("BE activado | ticket #", ticket, " | SL → ", DoubleToString(newSL, symDigits),
                " | tipo: ", isBuy ? "BUY" : "SELL");
   else   Print("BE ERROR    | ticket #", ticket, " | error: ", GetLastError(),
                " | tipo: ", isBuy ? "BUY" : "SELL",
                " | newSL: ", DoubleToString(newSL, symDigits),
                " | curPrice: ", DoubleToString(curPrice, symDigits));
}

//+------------------------------------------------------------------+
//| MOVER SL A NIVEL DE BENEFICIO                                    |
//| Retorna true si el SL fue movido exitosamente (o ya estaba alli) |
//+------------------------------------------------------------------+
bool MoveStopToProfit(ulong ticket, double profitPips)
{
   if(!posInfo.SelectByTicket(ticket)) return false;
   bool   isBuy     = (posInfo.PositionType() == POSITION_TYPE_BUY);
   double openPrice = posInfo.PriceOpen();
   double newSL     = isBuy
                      ? NormalizeDouble(openPrice + profitPips * pipSize, symDigits)
                      : NormalizeDouble(openPrice - profitPips * pipSize, symDigits);
   double currentSL = posInfo.StopLoss();

   // Para BUY: mover si newSL > currentSL, o si no hay SL (currentSL==0)
   // Para SELL: mover si newSL < currentSL, o si no hay SL (currentSL==0)
   bool shouldMove = (isBuy  && (currentSL == 0 || newSL > currentSL)) ||
                     (!isBuy && (currentSL == 0 || newSL < currentSL));
   if(!shouldMove) return true; // ya esta en ese nivel o mejor

   // Validar stops level, freeze level y lado del precio (v2.66)
   double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!ModificacionPermitida(isBuy, newSL, currentSL, posInfo.TakeProfit()))
   {
      static datetime ultimoAvisoSP = 0;
      if(TimeCurrent() - ultimoAvisoSP > 30)
      {
         Print("SP AVISO  | ticket #", ticket,
               " | SL ", DoubleToString(newSL, symDigits), " no permitido ahora (precio ",
               DoubleToString(curPrice, symDigits), ", stops/freeze level). Diferido.");
         ultimoAvisoSP = TimeCurrent();
      }
      return false; // diferir — el caller no marcara el checkpoint
   }

   bool ok = trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
   if(ok) Print("SP -> +", profitPips, " pips | ticket #", ticket,
                " | tipo: ", isBuy ? "BUY" : "SELL",
                " | newSL: ", DoubleToString(newSL, symDigits));
   else   Print("SP ERROR  | ticket #", ticket, " | error: ", GetLastError(),
                " | tipo: ", isBuy ? "BUY" : "SELL",
                " | newSL: ", DoubleToString(newSL, symDigits),
                " | curPrice: ", DoubleToString(curPrice, symDigits));
   return ok;
}

//+------------------------------------------------------------------+
//| APLICAR TRAILING STOP                                            |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, double trailingPips)
{
   if(!posInfo.SelectByTicket(ticket)) return;
   double trailDist = trailingPips * pipSize;
   double currentSL = posInfo.StopLoss();
   double currentTP = posInfo.TakeProfit();
   bool   isBuy     = (posInfo.PositionType() == POSITION_TYPE_BUY);
   // v2.66: mover solo si mejora al menos TrailingPasoPips (antes en cada tick)
   double paso      = MathMax(_Point, TrailingPasoPips * pipSize);

   double newSL = isBuy
                  ? NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - trailDist, symDigits)
                  : NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailDist, symDigits);

   bool mejora = (currentSL == 0) ||
                 ( isBuy && newSL - currentSL >= paso) ||
                 (!isBuy && currentSL - newSL >= paso);
   if(!mejora) return;
   if(!ModificacionPermitida(isBuy, newSL, currentSL, currentTP)) return;

   if(!trade.PositionModify(ticket, newSL, currentTP))
      Print("TS ERROR  | ticket #", ticket, " | ", trade.ResultRetcodeDescription(),
            " | newSL: ", DoubleToString(newSL, symDigits));
}

//+------------------------------------------------------------------+
//| SE PUEDE MODIFICAR EL SL AHORA? (v2.66)                          |
//| - nuevo SL del lado correcto del precio                          |
//| - a la distancia minima del broker (stops level)                 |
//| - SL/TP actuales fuera de la zona de congelacion (freeze level)  |
//+------------------------------------------------------------------+
bool ModificacionPermitida(bool isBuy, double newSL, double currentSL, double currentTP)
{
   double precio = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(precio <= 0) return false;
   if( isBuy && newSL >= precio) return false;
   if(!isBuy && newSL <= precio) return false;

   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   if(stops > 0 && MathAbs(precio - newSL) < stops) return false;
   if(freeze > 0)
   {
      if(currentSL != 0 && MathAbs(precio - currentSL) <= freeze) return false;
      if(currentTP != 0 && MathAbs(precio - currentTP) <= freeze) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| ELIMINAR TAKE PROFIT                                             |
//+------------------------------------------------------------------+
void RemoveTakeProfit(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;
   trade.PositionModify(ticket, posInfo.StopLoss(), 0);
}

//+------------------------------------------------------------------+
//| PERDIDA EN DIVISA DE LA CUENTA DE 1 LOTE CON UN SL DADO (v2.66)  |
//| Usa OrderCalcProfit (valor real del simbolo segun el terminal).  |
//| Respaldo: ValorPuntoPorLote si OrderCalcProfit no esta disponible|
//+------------------------------------------------------------------+
double PerdidaPorLote(double slDistance)
{
   if(slDistance <= 0) return 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pnl   = 0;
   if(price > 0 &&
      OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price - slDistance, pnl) &&
      pnl < 0)
      return -pnl;

   // Respaldo manual: valor de 1 pip por lote introducido por el usuario
   if(ValorPuntoPorLote > 0 && pipSize > 0)
   {
      static datetime ultimoAvisoRespaldo = 0;
      if(TimeCurrent() - ultimoAvisoRespaldo > 3600)
      {
         Print("[LOTES] OrderCalcProfit no disponible (error ", GetLastError(),
               ") — usando ValorPuntoPorLote como respaldo.");
         ultimoAvisoRespaldo = TimeCurrent();
      }
      return (slDistance / pipSize) * ValorPuntoPorLote;
   }
   return 0;
}

// Digitos decimales del volumen segun el paso de lote del broker
int VolumenDigitos()
{
   if(symLotStep <= 0) return 2;
   return (int)MathMax(0, MathCeil(-MathLog10(symLotStep) - 1e-9));
}

//+------------------------------------------------------------------+
//| CALCULAR LOTES POR % DE RIESGO                                   |
//| v2.66: la perdida por lote la calcula el terminal; si el lote    |
//| resultante es menor que el minimo devuelve 0 (no opera) en vez   |
//| de subirlo al minimo y exceder el riesgo.                        |
//+------------------------------------------------------------------+
double CalculateLots(double slDistance, double riskPct)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPct / 100.0;
   double lossPerLot = PerdidaPorLote(slDistance);

   if(riskAmount <= 0 || slDistance <= 0 || lossPerLot <= 0 || symLotStep <= 0) return 0;

   double lotsRaw = riskAmount / lossPerLot;
   double lots    = MathFloor(lotsRaw / symLotStep + 1e-9) * symLotStep;
   lots = NormalizeDouble(MathMin(symMaxLot, lots), VolumenDigitos());

   static datetime ultimoLog = 0;
   if(TimeCurrent() - ultimoLog > 60)
   {
      Print("[LOTES] Bal:$", DoubleToString(balance,2),
            " Riesgo:$", DoubleToString(riskAmount,2),
            " SL:", DoubleToString(slDistance / pipSize,1), "pips",
            " Perdida/lote:$", DoubleToString(lossPerLot,2),
            " → Lotes:", DoubleToString(lots, VolumenDigitos()),
            " RiesgoReal:$", DoubleToString(lossPerLot * lots, 2));
      ultimoLog = TimeCurrent();
   }

   if(lots < symMinLot)
   {
      static datetime ultimoAvisoMin = 0;
      if(TimeCurrent() - ultimoAvisoMin > 300)
      {
         Print("[LOTES] Lote calculado (", DoubleToString(lotsRaw, 4), ") menor que el minimo (",
               DoubleToString(symMinLot, VolumenDigitos()), "). No se opera: el minimo superaria el riesgo.");
         ultimoAvisoMin = TimeCurrent();
      }
      return 0;
   }

   return lots;
}

//+------------------------------------------------------------------+
//| CANCELAR ORDENES PENDIENTES                                      |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| CERRAR TODAS LAS POSICIONES                                      |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)     continue;
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| RESET DIARIO                                                     |
//+------------------------------------------------------------------+
void ResetDaily()
{
   // Guardar estadisticas del dia que termina ANTES de resetear
   CSVGuardarDia();

   // Generar reporte mensual:
   // - Si hoy es el ultimo dia del mes → generar reporte de este mes
   // - Si hoy es el primer dia del mes → generar reporte del mes anterior
   //   (cubre el caso de que el ultimo dia del mes no hubo operaciones)
   MqlDateTime dtHoy;
   TimeToStruct(TimeCurrent(), dtHoy);
   if(EsUltimoDiaMes(dtHoy))
   {
      CSVGenerarReporteMensual(dtHoy.year, dtHoy.mon);
   }
   else if(dtHoy.day == 1)
   {
      // Primer dia del nuevo mes — generar reporte del mes anterior si no existe
      int mesAnterior = dtHoy.mon - 1;
      int anioAnterior = dtHoy.year;
      if(mesAnterior == 0) { mesAnterior = 12; anioAnterior--; }
      string archivoRep = StringFormat("RRL_US30_Reporte_%04d_%02d.csv", anioAnterior, mesAnterior);
      int handle = FileOpen(archivoRep, FILE_READ|FILE_CSV);
      if(handle == INVALID_HANDLE)
      {
         // No existe aun → generarlo ahora
         Print("REPORTE: Generando reporte pendiente del mes anterior...");
         CSVGenerarReporteMensual(anioAnterior, mesAnterior);
      }
      else
         FileClose(handle);
   }

   rangeHigh               = 0;
   rangeLow                = 0;
   rangeSet                = false;
   rangeFijado             = false;
   rangoEnVivo             = false;
   RangoEliminar();
   NivelesEliminarTodo();
   lastRangeMin            = -1;
   VLinEliminar();
   lastPanelMin            = -1;
   cachePnLMin             = -1;
   cachePnLPct             = 0;
   cacheBalasHoyMin        = -1;
   cacheBalasHoy           = 0;
   cierreNYHecho           = false;
   nivelesNYDibujados      = false;
   londresIniciadoAlertado = false;
   festivoAlertado         = false;
   cierreNYAlertado        = false;
   balaEnCurso             = false;
   balaActual              = 0;
   horaprimeraBala         = 0;
   balasConSL              = 0;
   balasConTP              = 0;
   balasConBE              = 0;
   balasConSP              = 0;
   limiteDiarioAlertado    = false;
   tpDiarioAlcanzado       = false;
   opuestaAlertadaBala     = -1;
   balanceInicioDia        = AccountInfoDouble(ACCOUNT_BALANCE);
   inicioDiaOperativo      = TimeCurrent();
   velasConfirmadas        = 0;
   ultimaVelaContada       = 0;
   esperandoConfirmacion   = false;
   precioFueraRango        = false;
   CSVResetContadores();

   for(int i = 0; i < 8; i++)
   {
      balas[i].id        = i + 1;
      balas[i].direction = 0;
      balas[i].active    = false;
      balas[i].e2Abierta = false;
      balas[i].cp1Done   = false;
      balas[i].tp1Done   = false;
      balas[i].cp3Done   = false;
      balas[i].tp2Done   = false;
      balas[i].terminada = false;
      balas[i].resultado = "NA";
   }

   CancelPendingOrders();

   // Alerta Telegram si manana es festivo
   if(esFestMananUS || esFestMananUK)
   {
      string mercado = esFestMananUS ? "🇺🇸 EE.UU." : "🇬🇧 Reino Unido";
      if(esFestMananUS && esFestMananUK) mercado = "🇺🇸 EE.UU. y 🇬🇧 Reino Unido";
      TelegramSend("📅 <b>AVISO — FESTIVO MAÑANA</b>\n"
                   "----------------\n"
                   "Festivo: " + mercado + "\n"
                   "El bot <b>no operará</b> mañana.");
   }

   Print("--- RESET DIARIO ---");
   Print(" Balance: $", DoubleToString(balanceInicioDia, 2),
         " | Riesgo/bala:", RiskPerBala, "%",
         " | Limite:-", MaxDailyLossPct, "%");
   Print(" Horas: Londres ", londonStartH, ":00-", londonEndH,
         ":59 | NY ", nyOpenH, ":00-", cancelH, ":00 | Cierre ", closeAllH, ":00");
}

//+------------------------------------------------------------------+
//| FESTIVOS DE EEUU                                                 |
//| NYSE cierra estos dias — no hay sesion NY                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| NOMBRE DEL FESTIVO ACTIVO                                        |
//+------------------------------------------------------------------+
string GetNombreFestivo()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(esFestivoHoyUS)
   {
      // Reproducir la misma logica de EsFestivoUS para obtener el nombre
      int m = dt.mon, d = dt.day, dow = dt.day_of_week;
      // Año Nuevo
      if(m==1 && d==1)                                      return "Año Nuevo (NYSE)";
      if(m==12 && d==31 && dow==5)                          return "Año Nuevo - Observancia (NYSE)";
      if(m==1 && d==2 && dow==1)                            return "Año Nuevo - Observancia (NYSE)";
      // MLK Day (3er lunes de enero)
      if(m==1 && dow==1 && d>=15 && d<=21)                  return "Martin Luther King Jr. Day (NYSE)";
      // Presidents Day (3er lunes de febrero)
      if(m==2 && dow==1 && d>=15 && d<=21)                  return "Presidents' Day (NYSE)";
      // Memorial Day (último lunes de mayo)
      if(m==5 && dow==1 && d>=25)                           return "Memorial Day (NYSE)";
      // Juneteenth
      if(m==6 && d==19)                                     return "Juneteenth (NYSE)";
      if(m==6 && d==18 && dow==5)                           return "Juneteenth - Observancia (NYSE)";
      if(m==6 && d==20 && dow==1)                           return "Juneteenth - Observancia (NYSE)";
      // Independence Day
      if(m==7 && d==4)                                      return "Independence Day (NYSE)";
      if(m==7 && d==3 && dow==5)                            return "Independence Day - Observancia (NYSE)";
      if(m==7 && d==5 && dow==1)                            return "Independence Day - Observancia (NYSE)";
      // Labor Day (1er lunes de septiembre)
      if(m==9 && dow==1 && d<=7)                            return "Labor Day (NYSE)";
      // Thanksgiving (4to jueves de noviembre)
      if(m==11 && dow==4 && d>=22 && d<=28)                 return "Thanksgiving (NYSE)";
      // Navidad
      if(m==12 && d==25)                                    return "Navidad (NYSE)";
      if(m==12 && d==24 && dow==5)                          return "Navidad - Observancia (NYSE)";
      if(m==12 && d==26 && dow==1)                          return "Navidad - Observancia (NYSE)";
      return "Festivo NYSE";
   }
   if(esFestivoHoyUK)
   {
      int m = dt.mon, d = dt.day, dow = dt.day_of_week;
      if(m==1 && d==1)                                      return "Año Nuevo (LSE)";
      if(m==1 && d==2 && dow==1)                            return "Año Nuevo - Observancia (LSE)";
      if(m==12 && d==25)                                    return "Navidad (LSE)";
      if(m==12 && d==26)                                    return "Boxing Day (LSE)";
      if(m==12 && d==27 && dow==1)                          return "Boxing Day - Observancia (LSE)";
      if(m==12 && d==28 && dow==1)                          return "Navidad/Boxing Day - Observancia (LSE)";
      if(m==5 && d==1 && dow==1)                            return "Early May Bank Holiday (LSE)";
      if(m==5 && d>=25 && dow==1)                           return "Spring Bank Holiday (LSE)";
      if(m==8 && d>=25 && dow==1)                           return "Summer Bank Holiday (LSE)";
      return "Festivo LSE";
   }
   return "";
}

bool EsFestivoUS(MqlDateTime &dt)
{
   if(!FiltrarFestivosUS) return false;

   int d = dt.day;
   int m = dt.mon;
   int y = dt.year;

   // --- Festivos con fecha fija ---
   // Año Nuevo: 1 enero (si cae fin de semana, se observa el lunes/viernes)
   if(m==1  && d==1)  return true;

   // Dia de la Independencia: 4 julio
   if(m==7  && d==4)  return true;

   // Dia de Navidad: 25 diciembre
   if(m==12 && d==25) return true;

   // Dia de Veteranos: 11 noviembre (NYSE no cierra, pero Juneteenth si)
   // Juneteenth: 19 junio (desde 2021)
   if(y >= 2021 && m==6 && d==19) return true;

   // --- Festivos con fecha variable (lunes especificos) ---
   // Martin Luther King: 3er lunes de enero
   if(m==1 && dt.day_of_week==1)
   {
      int semana = (d-1)/7 + 1;
      if(semana == 3) return true;
   }

   // Dia del Presidente: 3er lunes de febrero
   if(m==2 && dt.day_of_week==1)
   {
      int semana = (d-1)/7 + 1;
      if(semana == 3) return true;
   }

   // Memorial Day: ultimo lunes de mayo
   if(m==5 && dt.day_of_week==1 && d>=25) return true;

   // Labor Day: primer lunes de septiembre
   if(m==9 && dt.day_of_week==1 && d<=7) return true;

   // Dia de Accion de Gracias: 4to jueves de noviembre
   if(m==11 && dt.day_of_week==4)
   {
      int semana = (d-1)/7 + 1;
      if(semana == 4) return true;
   }

   // Viernes despues de Accion de Gracias (NYSE cierra temprano, evitamos el dia)
   if(m==11 && dt.day_of_week==5)
   {
      // Si ayer fue el 4to jueves de noviembre
      MqlDateTime dtAyer;
      TimeToStruct(TimeCurrent() - 86400, dtAyer);
      if(dtAyer.mon==11 && dtAyer.day_of_week==4)
      {
         int semana = (dtAyer.day-1)/7 + 1;
         if(semana == 4) return true;
      }
   }

   // Observancia: si festivo fijo cae sabado → viernes anterior no opera
   // si cae domingo → lunes siguiente no opera
   // Año Nuevo
   if(m==12 && d==31 && dt.day_of_week==5) return true; // 1 ene cae sabado
   if(m==1  && d==2  && dt.day_of_week==1) return true; // 1 ene cae domingo
   // Independencia
   if(m==7 && d==3  && dt.day_of_week==5) return true;  // 4 jul cae sabado
   if(m==7 && d==5  && dt.day_of_week==1) return true;  // 4 jul cae domingo
   // Navidad
   if(m==12 && d==24 && dt.day_of_week==5) return true; // 25 dic cae sabado
   if(m==12 && d==26 && dt.day_of_week==1) return true; // 25 dic cae domingo
   // Juneteenth
   if(y>=2021 && m==6 && d==18 && dt.day_of_week==5) return true;
   if(y>=2021 && m==6 && d==20 && dt.day_of_week==1) return true;

   return false;
}

//+------------------------------------------------------------------+
//| FESTIVOS DE REINO UNIDO (Bank Holidays — LSE)                    |
//+------------------------------------------------------------------+
bool EsFestivoUK(MqlDateTime &dt)
{
   if(!FiltrarFestivosUK) return false;

   int d = dt.day;
   int m = dt.mon;
   int y = dt.year;

   // --- Año Nuevo: 1 enero ---
   if(m==1 && d==1) return true;
   // Observancia: si cae domingo → lunes
   if(m==1 && d==2 && dt.day_of_week==1) return true;

   // --- Good Friday (Viernes Santo): variable ---
   // Se calcula con el algoritmo de Easter
   // Easter Sunday calculation (Anonymous Gregorian)
   {
      int a = y % 19;
      int b = y / 100;
      int c = y % 100;
      int d2= b / 4;
      int e = b % 4;
      int f = (b + 8) / 25;
      int g = (b - f + 1) / 3;
      int h = (19*a + b - d2 - g + 15) % 30;
      int i = c / 4;
      int k = c % 4;
      int l = (32 + 2*e + 2*i - h - k) % 7;
      int n2= (a + 11*h + 22*l) / 451;
      int easterMonth = (h + l - 7*n2 + 114) / 31;
      int easterDay   = ((h + l - 7*n2 + 114) % 31) + 1;
      // Good Friday = Easter - 2 dias
      datetime easter  = StringToTime(StringFormat("%04d.%02d.%02d", y, easterMonth, easterDay));
      datetime goodFri = easter - 2 * 86400;
      // Easter Monday = Easter + 1 dia
      datetime easterMon = easter + 86400;
      MqlDateTime dtGF, dtEM;
      TimeToStruct(goodFri,   dtGF);
      TimeToStruct(easterMon, dtEM);
      if(dt.mon == dtGF.mon && dt.day == dtGF.day) return true;  // Good Friday
      if(dt.mon == dtEM.mon && dt.day == dtEM.day) return true;  // Easter Monday
   }

   // --- Early May Bank Holiday: primer lunes de mayo ---
   // Excepcion: en 2020 se movio al 8 mayo (VE Day)
   if(m==5 && dt.day_of_week==1)
   {
      if(y==2020 && d==8)  return true;
      if(y!=2020 && d<=7)  return true;
   }

   // --- Spring Bank Holiday: ultimo lunes de mayo ---
   // Excepcion: en 2022 se movio al 2 junio (Jubileo)
   if(y==2022 && m==6 && d==2  && dt.day_of_week==4) return true; // Jueves
   if(y==2022 && m==6 && d==3  && dt.day_of_week==5) return true; // Viernes
   if(y!=2022 && m==5 && dt.day_of_week==1 && d>=25) return true;

   // --- Summer Bank Holiday: ultimo lunes de agosto ---
   if(m==8 && dt.day_of_week==1 && d>=25) return true;

   // --- Navidad: 25 diciembre ---
   if(m==12 && d==25) return true;
   // Observancia
   if(m==12 && d==26 && dt.day_of_week==1) return true; // 25 dic domingo → lunes
   if(m==12 && d==27 && dt.day_of_week==2) return true; // 25 dic sabado → martes

   // --- Boxing Day: 26 diciembre ---
   if(m==12 && d==26) return true;
   // Observancia
   if(m==12 && d==27 && dt.day_of_week==1) return true; // 26 dic domingo → lunes
   if(m==12 && d==28 && dt.day_of_week==2) return true; // 26 dic sabado → martes

   return false;
}

//+------------------------------------------------------------------+
//| DIA DE LA SEMANA                                                 |
//+------------------------------------------------------------------+
bool CanTradeToday(int dayOfWeek)
{
   // Usar flags precalculados en RecalcHours — no recalcular en cada tick
   if(esFestivoHoyUS || esFestivoHoyUK)
   {
      // Log periodico
      static datetime ultimoAvisoFest = 0;
      if(TimeCurrent() - ultimoAvisoFest > 3600)
      {
         Print(esFestivoHoyUS ? "HOY ES FESTIVO US — bot en pausa." : "HOY ES FESTIVO UK — bot en pausa.");
         ultimoAvisoFest = TimeCurrent();
      }

      // Telegram al inicio de la sesion de Londres — una sola vez por dia
      MqlDateTime dtF;
      TimeToStruct(TimeCurrent(), dtF);
      int nowMinF = dtF.hour * 60 + dtF.min;
      int londonStartF = londonStartH * 60 + londonStartM;
      if(!festivoAlertado && nowMinF >= londonStartF)
      {
         string nombre = GetNombreFestivo();
         string fechaStr = IntegerToString(dtF.year) + "-" +
                           (dtF.mon  < 10 ? "0" : "") + IntegerToString(dtF.mon)  + "-" +
                           (dtF.day  < 10 ? "0" : "") + IntegerToString(dtF.day);
         TelegramSend("📅 <b>DÍA NO OPERATIVO</b>\n" +
            "----------------\n" +
            "Motivo:   " + nombre + "\n" +
            "Fecha:    " + fechaStr + "\n" +
            "Londres:  " + IntegerToString(londonStartH) + ":00 - " + IntegerToString(londonEndH) + ":59\n" +
            "NY Open:  " + IntegerToString(nyOpenH) + ":00\n" +
            "ℹ️ El bot reanudará operaciones el próximo día hábil.");
         Print("[FESTIVO] Telegram enviado: ", nombre);
         festivoAlertado = true;
      }
      return false;
   }

   switch(dayOfWeek)
   {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| EVENTO DE TRANSACCION                                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   // Una orden pendiente se activo (se convirtio en posicion)
   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE &&
      trans.order_state == ORDER_STATE_FILLED)
   {
      int idx = balaActual - 1;
      if(idx < 0 || idx > 7) return;

      string tag = TradeComment + "_B" + IntegerToString(idx+1);

      // Determinar la direccion activada
      int dirActivada = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic()  != MagicNumber) continue;
         if(posInfo.Symbol() != _Symbol)     continue;
         if(StringFind(posInfo.Comment(), tag) < 0) continue;
         dirActivada = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         break;
      }

      if(dirActivada == 0) return;

      // Cancelar INMEDIATAMENTE las ordenes de la direccion opuesta
      CancelOrdenesOpuestas(tag, dirActivada);
      balas[idx].direction = dirActivada;

      // Actualizar niveles en grafico para la direccion activada
      double slDist  = StopLossPips * pipSize;
      double tp1Dist = TP1Pips      * pipSize;
      double tp2Dist = TP2Pips      * pipSize;
      Print("BALA ", idx+1, " | ", (dirActivada==1 ? "BUY" : "SELL"),
            " activado | Ordenes opuestas canceladas inmediatamente");
   }

   // Una posicion fue cerrada — verificar si la bala termino
   // y si corresponde evaluar nueva bala de inmediato
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // v2.66: un deal nuevo cambia el PnL del dia — invalidar la cache
      cachePnLMin = -1;

      int idx = balaActual - 1;
      if(idx < 0 || idx > 7) return;
      if(!balas[idx].active) return;

      string tag = TradeComment + "_B" + IntegerToString(idx+1);

      // Verificar si quedan posiciones u ordenes de esta bala
      bool hayPosiciones = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Magic()  != MagicNumber) continue;
         if(posInfo.Symbol() != _Symbol)     continue;
         if(StringFind(posInfo.Comment(), tag) < 0) continue;
         hayPosiciones = true;
         break;
      }

      bool hayOrdenes = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
         if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0) continue;
         hayOrdenes = true;
         break;
      }

      // Si no queda nada → la bala termino, ManageCheckpoints lo procesara
      // en el siguiente tick. No forzar aqui para evitar condiciones de carrera.
      if(!hayPosiciones && !hayOrdenes)
         Print("BALA ", idx+1, " | Todas las posiciones cerradas — procesando en siguiente tick");
   }
}

//+------------------------------------------------------------------+
//| CANCELAR SOLO LAS ORDENES DE LA DIRECCION OPUESTA                |
//+------------------------------------------------------------------+
void CancelOrdenesOpuestas(string tag, int dirActivada)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0) continue;

      long orderType = OrderGetInteger(ORDER_TYPE);

      // Si se activo BUY → cancelar SELL Stop pendientes de esta bala
      // Si se activo SELL → cancelar BUY Stop pendientes de esta bala
      bool esOpuesta = (dirActivada ==  1 && orderType == ORDER_TYPE_SELL_STOP) ||
                       (dirActivada == -1 && orderType == ORDER_TYPE_BUY_STOP);

      if(esOpuesta)
         trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//|                   ALERTAS TELEGRAM                               |
//+------------------------------------------------------------------+
//  MT5 permite llamadas HTTP via WebRequest()                       
//  Requiere activar: Herramientas → Opciones → Expert Advisors      
//  → "Permitir solicitudes Web" → agregar: https://api.telegram.org
//+------------------------------------------------------------------+

// v2.66: los mensajes se ENCOLAN y se envian desde OnTimer (1 por segundo).
// Antes WebRequest (sincrono, timeout 3 s) se ejecutaba dentro de OnTick y podia
// bloquear el EA varios segundos justo al cerrar o gestionar una bala.
#define TELEGRAM_COLA_MAX 50
string colaTelegram[];

void TelegramSend(string mensaje)
{
   if(!TelegramEnabled) return;
   // En el probador WebRequest no esta disponible: no encolar nada
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(TelegramToken == "TU_BOT_TOKEN" || TelegramChatID == "TU_CHAT_ID")
   {
      static datetime ultimoAvisoConfig = 0;
      if(TimeCurrent() - ultimoAvisoConfig > 3600)
      {
         Print("TELEGRAM: Configura TelegramToken y TelegramChatID en los parametros.");
         ultimoAvisoConfig = TimeCurrent();
      }
      return;
   }

   int n = ArraySize(colaTelegram);
   if(n >= TELEGRAM_COLA_MAX)
   {
      ArrayRemove(colaTelegram, 0, 1); // descartar el mas antiguo
      n = ArraySize(colaTelegram);
   }
   ArrayResize(colaTelegram, n + 1);
   colaTelegram[n] = mensaje;
}

// Enviar hasta maxMensajes de la cola (los mas antiguos primero)
void TelegramProcesarCola(int maxMensajes)
{
   for(int k = 0; k < maxMensajes && ArraySize(colaTelegram) > 0; k++)
   {
      string msg = colaTelegram[0];
      ArrayRemove(colaTelegram, 0, 1);
      TelegramEnviarAhora(msg);
   }
}

void OnTimer()
{
   TelegramProcesarCola(1);
}

// Envio sincrono via WebRequest — solo desde OnTimer / OnDeinit
void TelegramEnviarAhora(string mensaje)
{
   // Codificar mensaje para URL
   string msgEscaped = mensaje;
   StringReplace(msgEscaped, "%",  "%25"); // siempre primero
   StringReplace(msgEscaped, "&",  "%26");
   StringReplace(msgEscaped, "+",  "%2B");
   StringReplace(msgEscaped, "#",  "%23");
   StringReplace(msgEscaped, "\n", "%0A");
   StringReplace(msgEscaped, " ",  "%20");

   string url = "https://api.telegram.org/bot" + TelegramToken
              + "/sendMessage?chat_id=" + TelegramChatID
              + "&parse_mode=HTML"
              + "&text=" + msgEscaped;

   char   postData[];
   char   result[];
   string responseHeaders;

   int res = WebRequest(
      "GET",
      url,
      "",
      3000,
      postData,
      result,
      responseHeaders
   );

   if(res == -1)
      Print("TELEGRAM ERROR: ", GetLastError(),
            " | Verifica que https://api.telegram.org este en la lista blanca de MT5");
   else
   {
      string resp = CharArrayToString(result);
      if(StringFind(resp, "\"ok\":false") >= 0)
         Print("TELEGRAM rechazado: ", resp);
   }
}

// Formatear mensaje con emoji y datos clave
void TelegramBalaLanzada(int numBala, double rangePips, int dir, double pnlNeto, double margen)
{
   string dirStr = dir == 1 ? "BUY  📈" : (dir == -1 ? "SELL 📉" : "PENDIENTE ⏳");
   string msg =
      "<b>🚀 BALA " + IntegerToString(numBala) + " LANZADA</b>\n" +
      "----------------\n" +
      "Par:       US30\n" +
      "Rango LDN: " + DoubleToString(rangePips, 1) + " pips\n" +
      "SL:        " + DoubleToString(StopLossPips, 0) + " pips\n" +
      "TP1/TP2:   " + DoubleToString(TP1Pips,0) + " / " + DoubleToString(TP2Pips,0) + " pips\n" +
      "Riesgo:    " + DoubleToString(RiskPerBala,1) + "%\n" +
      "----------------\n" +
      "PnL dia:   " + DoubleToString(pnlNeto,2) + "%\n" +
      "Margen:    " + DoubleToString(margen,2) + "% libre\n" +
      "Balas:     " + IntegerToString(numBala) + "/" + IntegerToString(GetTotalBalasMax()) + " hoy";
   TelegramSend(msg);
}

void TelegramCheckpoint(int numBala, int cp, string descripcion, double pips)
{
   string nombres[] = {"", "CP1 Break Even", "TP1 Cierre E1", "CP3 SP+100", "TP2 Cierre E2"};
   string emojis[]  = {"", "🔒", "💰", "🛡", "🎯"};
   string nombre = (cp >= 1 && cp <= 4) ? nombres[cp] : "CP"+IntegerToString(cp);
   string emoji  = (cp >= 1 && cp <= 4) ? emojis[cp]  : "✅";
   string msg =
      emoji + " <b>" + nombre + " — BALA " + IntegerToString(numBala) + "</b>\n" +
      "----------------\n" +
      "Accion:  " + descripcion + "\n" +
      "Nivel:   +" + DoubleToString(pips, 0) + " pips\n" +
      "Par:     US30";
   TelegramSend(msg);
}

void TelegramLimiteDiario(double pnlNeto, int numBalasConSL, int numBalasConTP)
{
   string msg =
      "🛑 <b>LIMITE DIARIO ALCANZADO</b>\n" +
      "----------------\n" +
      "Par:      US30\n" +
      "PnL dia:  -" + DoubleToString(pnlNeto, 2) + "%\n" +
      "Limite:   -" + DoubleToString(MaxDailyLossPct, 1) + "%\n" +
      "Balas SL: " + IntegerToString(numBalasConSL) + "\n" +
      "Balas BE: " + IntegerToString(balasConBE) + "\n" +
      "Balas SP: " + IntegerToString(balasConSP) + "\n" +
      "Balas TP: " + IntegerToString(numBalasConTP) + "\n" +
      "No se lanzan mas balas hoy.";
   TelegramSend(msg);
}

void TelegramBotIniciado()
{
   string msg =
      "✅ <b>BOT RRL-US30 INICIADO</b>\n" +
      "----------------\n" +
      "GMT offset: GMT+" + IntegerToString(brokerOffsetHours) + "\n" +
      "Londres:   " + IntegerToString(londonStartH) + ":00 - " + IntegerToString(londonEndH) + ":59\n" +
      "NY Open:   " + IntegerToString(nyOpenH) + ":00 - " + IntegerToString(cancelH) + ":00\n" +
      "Cierre:    " + IntegerToString(closeAllH) + ":00\n" +
      "Riesgo/bala: " + DoubleToString(RiskPerBala,1) + "%\n" +
      "Limite/dia:  " + DoubleToString(MaxDailyLossPct,1) + "%\n" +
      "Balance:   $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   TelegramSend(msg);
}

void TelegramBotDetenido(string razon)
{
   string msg =
      "⛔ <b>BOT RRL-US30 DETENIDO</b>\n" +
      "----------------\n" +
      "Razon: " + razon + "\n" +
      "Balas hoy: " + IntegerToString(balaActual) + "/" + IntegerToString(GetTotalBalasMax()) +
      " (" + IntegerToString(balasConTP) + "TP " + IntegerToString(balasConSP) + "SP "
      + IntegerToString(balasConBE) + "BE " + IntegerToString(balasConSL) + "SL)";
   TelegramSend(msg);
}

void TelegramEntradaCerrada(int numBala, int entrada, string tipo, double pips, double pnlNeto)
{
   string emoji;
   string titulo;
   string resultado;

   if(tipo == "TP")
   {
      emoji    = "💰";
      titulo   = "E" + IntegerToString(entrada) + " CERRADA EN TP";
      resultado= "TP en +" + DoubleToString(pips,0) + " pips";
   }
   else if(tipo == "SL")
   {
      emoji    = "❌";
      titulo   = "E" + IntegerToString(entrada) + " CERRADA EN SL";
      resultado= "SL — perdida real";
   }
   else if(tipo == "BE")
   {
      emoji    = "⚪";
      titulo   = "E" + IntegerToString(entrada) + " CERRADA EN BE";
      resultado= "Break Even — sin perdida";
   }
   else if(tipo == "SP")
   {
      emoji    = "🔵";
      titulo   = "E" + IntegerToString(entrada) + " CERRADA EN SP";
      resultado= "Stop Profit en +" + DoubleToString(pips,0) + " pips";
   }
   else
   {
      emoji    = "⚠️";
      titulo   = "E" + IntegerToString(entrada) + " CERRADA";
      resultado= "Cierre manual";
   }

   string msg =
      emoji + " <b>BALA " + IntegerToString(numBala) + " — " + titulo + "</b>\n" +
      "----------------\n" +
      "Entrada:   E" + IntegerToString(entrada) + " de 2\n" +
      "Resultado: " + resultado + "\n" +
      "PnL dia:   " + (pnlNeto>=0?"+":"") + DoubleToString(pnlNeto,2) + "%\n" +
      "Par:       US30";
   TelegramSend(msg);
}

void TelegramBalaTerminada(int numBala, string tipoE1, string tipoE2, double pnlNeto)
{
   double margen = MaxDailyLossPct + pnlNeto;

   // Determinar resultado global
   bool noActivada = (tipoE1=="NA" && tipoE2=="NA");
   bool haySL  = (tipoE1=="SL" || tipoE2=="SL");
   bool hayTP  = (tipoE1=="TP" || tipoE2=="TP");
   bool haySP  = !haySL && (tipoE1=="SP" || tipoE2=="SP");
   bool soloBE = !haySL && !hayTP && !haySP;

   string emoji, result;
   if(noActivada)    { emoji = "⚪"; result = "CANCELADA"; }
   else if(haySL)    { emoji = "❌"; result = "CON SL";    }
   else if(hayTP)    { emoji = "✅"; result = "CON TP";    }
   else if(haySP)    { emoji = "🔵"; result = "CON SP";    }
   else              { emoji = "⚪"; result = "EN BE";     }

   // Texto legible por entrada
   string txtE1 = (tipoE1=="NA") ? "no activada" : tipoE1;
   string txtE2 = (tipoE2=="NA") ? "no activada" : tipoE2;

   string msg =
      emoji + " <b>BALA " + IntegerToString(numBala) + " CERRADA " + result + "</b>\n" +
      "----------------\n" +
      "E1: " + txtE1 + "  |  E2: " + txtE2 + "\n" +
      "PnL dia:  " + (pnlNeto>=0?"+":"") + DoubleToString(pnlNeto,2) + "%\n" +
      "Margen:   " + DoubleToString(margen,2) + "% libre\n" +
      "Balas:    " + IntegerToString(balasConTP) + "TP " +
                     IntegerToString(balasConSP) + "SP " +
                     IntegerToString(balasConBE) + "BE " +
                     IntegerToString(balasConSL) + "SL" +
      "  Total=" + IntegerToString(balaActual) + "/" + IntegerToString(GetTotalBalasMax());
   TelegramSend(msg);
}

//+------------------------------------------------------------------+
#define NIVELES_PREFIX "RRL_NVL_"

//+------------------------------------------------------------------+
//| CREAR O ACTUALIZAR LINEA DE NIVEL CON ETIQUETA                   |
//+------------------------------------------------------------------+
void NivelLinea(string id, double precio, color clr, int grosor, ENUM_LINE_STYLE estilo,
                datetime tInicio, datetime tFin, string etiqueta)
{
   // Linea de tiempo (segmento de inicio a fin de ventana NY)
   string nLin = NIVELES_PREFIX + id;
   if(ObjectFind(0, nLin) < 0)
      ObjectCreate(0, nLin, OBJ_TREND, 0, (long)tInicio, (double)precio, (long)tFin, (double)precio);
   ObjectSetInteger(0, nLin, OBJPROP_TIME, 0, (long)tInicio);
   ObjectSetDouble(0, nLin, OBJPROP_PRICE, 0, precio);
   ObjectSetInteger(0, nLin, OBJPROP_TIME, 1, (long)tFin);
   ObjectSetDouble(0, nLin, OBJPROP_PRICE, 1, precio);
   ObjectSetInteger(0, nLin, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, nLin, OBJPROP_WIDTH,       grosor);
   ObjectSetInteger(0, nLin, OBJPROP_STYLE,       estilo);
   ObjectSetInteger(0, nLin, OBJPROP_RAY_RIGHT,   false);
   ObjectSetInteger(0, nLin, OBJPROP_RAY_LEFT,    false);
   ObjectSetInteger(0, nLin, OBJPROP_BACK,        true);
   ObjectSetInteger(0, nLin, OBJPROP_SELECTABLE,  false);
   ObjectSetString(0,  nLin, OBJPROP_TOOLTIP,     etiqueta + " @ " + DoubleToString(precio, symDigits));

   // Etiqueta al final de la linea
   string nLbl = NIVELES_PREFIX + id + "_LBL";
   if(ObjectFind(0, nLbl) < 0)
      ObjectCreate(0, nLbl, OBJ_TEXT, 0, (long)tFin, (double)precio);
   ObjectSetInteger(0, nLbl, OBJPROP_TIME, (long)tFin);
   ObjectSetDouble(0,  nLbl, OBJPROP_PRICE,       precio);
   ObjectSetString(0,  nLbl, OBJPROP_TEXT,        " " + etiqueta);
   ObjectSetString(0,  nLbl, OBJPROP_FONT,        "Consolas");
   ObjectSetInteger(0, nLbl, OBJPROP_FONTSIZE,    8);
   ObjectSetInteger(0, nLbl, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, nLbl, OBJPROP_ANCHOR,      ANCHOR_LEFT);
   ObjectSetInteger(0, nLbl, OBJPROP_BACK,        false);
   ObjectSetInteger(0, nLbl, OBJPROP_SELECTABLE,  false);
}

//+------------------------------------------------------------------+
//| DIBUJAR TODOS LOS NIVELES DE UNA BALA                            |
//+------------------------------------------------------------------+
void NivelesDisbujar(int idx, double entryBuy, double entrySell,
                     double slBuy, double slSell,
                     double tp1Buy, double tp1Sell,
                     double tp2Buy, double tp2Sell)
{
   if(!NivelesVisible) return;

   // Tiempo: desde NY Open hasta cierre de ventana
   datetime ahora   = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(ahora, dt);
   int minActual  = dt.hour * 60 + dt.min;
   int minNYOpen  = nyOpenH * 60;
   int minCancel  = cancelH * 60;
   if(minCancel <= minNYOpen) minCancel += 1440;

   // tInicio = barra de NY Open del dia actual
   datetime tInicio = ahora - (minActual - minNYOpen) * 60;
   if(minActual < minNYOpen) tInicio = ahora - (minActual + 1440 - minNYOpen) * 60;
   // tFin = cierre de ventana
   datetime tFin = tInicio + (minCancel - minNYOpen) * 60;

   string b = IntegerToString(idx + 1);
   double cp1Buy  = entryBuy  + CP1Pips  * pipSize;
   double cp3Buy  = entryBuy  + CP3Pips  * pipSize;
   double cp1Sell = entrySell - CP1Pips  * pipSize;
   double cp3Sell = entrySell - CP3Pips  * pipSize;

   // --- BUY ---
   NivelLinea("B"+b+"_BUY_ENTRY", entryBuy, NvlClrEntrada, NvlGrosor, NvlEstilo, tInicio, tFin, "Buy");
   NivelLinea("B"+b+"_BUY_SL",    slBuy,    NvlClrSL,      NvlGrosor, NvlEstilo, tInicio, tFin, "SL");
   NivelLinea("B"+b+"_BUY_CP1",   cp1Buy,   NvlClrCP1,     NvlGrosor, NvlEstilo, tInicio, tFin, "CP1 Buy");
   NivelLinea("B"+b+"_BUY_TP1",   tp1Buy,   NvlClrTP1,     NvlGrosor, NvlEstilo, tInicio, tFin, "TP1 Buy");
   NivelLinea("B"+b+"_BUY_CP3",   cp3Buy,   NvlClrCP3,     NvlGrosor, NvlEstilo, tInicio, tFin, "CP3 Buy");
   NivelLinea("B"+b+"_BUY_TP2",   tp2Buy,   NvlClrTP2,     NvlGrosor, NvlEstilo, tInicio, tFin, "TP2 Buy");

   // --- SELL ---
   NivelLinea("B"+b+"_SEL_ENTRY", entrySell, NvlClrEntrada, NvlGrosor, NvlEstilo, tInicio, tFin, "Sell");
   NivelLinea("B"+b+"_SEL_SL",    slSell,    NvlClrSL,      NvlGrosor, NvlEstilo, tInicio, tFin, "SL");
   NivelLinea("B"+b+"_SEL_CP1",   cp1Sell,   NvlClrCP1,     NvlGrosor, NvlEstilo, tInicio, tFin, "CP1 Sell");
   NivelLinea("B"+b+"_SEL_TP1",   tp1Sell,   NvlClrTP1,     NvlGrosor, NvlEstilo, tInicio, tFin, "TP1 Sell");
   NivelLinea("B"+b+"_SEL_CP3",   cp3Sell,   NvlClrCP3,     NvlGrosor, NvlEstilo, tInicio, tFin, "CP3 Sell");
   NivelLinea("B"+b+"_SEL_TP2",   tp2Sell,   NvlClrTP2,     NvlGrosor, NvlEstilo, tInicio, tFin, "TP2 Sell");

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ELIMINAR NIVELES DE UNA BALA                                     |
//+------------------------------------------------------------------+
void NivelesEliminarBala(int idx)
{
   string b = IntegerToString(idx + 1);
   string dirs[]   = {"BUY","SEL"};
   string niveles[] = {"ENTRY","SL","CP1","TP1","CP3","TP2"};
   for(int d = 0; d < 2; d++)
      for(int n = 0; n < 6; n++)
      {
         string base = NIVELES_PREFIX + "B" + b + "_" + dirs[d] + "_" + niveles[n];
         if(ObjectFind(0, base)          >= 0) ObjectDelete(0, base);
         if(ObjectFind(0, base+"_LBL")   >= 0) ObjectDelete(0, base+"_LBL");
      }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ELIMINAR TODOS LOS NIVELES                                       |
//+------------------------------------------------------------------+
void NivelesEliminarTodo()
{
   ObjectsDeleteAll(0, NIVELES_PREFIX);
   ChartRedraw(0);
}

#define VLIN_PREFIX "RRL_VLIN_"

//+------------------------------------------------------------------+
//| DIBUJAR LINEAS VERTICALES DE SESION                              |
//+------------------------------------------------------------------+
void VLinDisbujar()
{
   datetime ahora = TimeCurrent();
   MqlDateTime dtA;
   TimeToStruct(ahora, dtA);
   datetime inicioDia = ahora - dtA.hour * 3600 - dtA.min * 60 - dtA.sec;

   datetime tNY = inicioDia + nyOpenH * 3600;

   // Los viernes usar la ventana reducida igual que en OnTick
   int cancelHEfectivo = cancelH;
   if(dtA.day_of_week == 5 && VentanaViernesPips < 4)
      cancelHEfectivo = nyOpenH + VentanaViernesPips;

   datetime tCancel = inicioDia + cancelHEfectivo * 3600;
   if(tCancel <= tNY) tCancel += 86400; // cruce medianoche

   // Los viernes closeTime = CierreViernesBroker (si esta activo)
   int closeHEfectivo = (dtA.day_of_week == 5 && CierreViernesBroker >= 0) ? CierreViernesBroker : closeAllH;
   datetime tClose = inicioDia + closeHEfectivo * 3600;

   // Linea NY Open
   if(VLinNYVisible)
   {
      string n = VLIN_PREFIX + "NY";
      if(ObjectFind(0, n) < 0)
         ObjectCreate(0, n, OBJ_VLINE, 0, (long)tNY, (double)0);
      ObjectSetInteger(0, n, OBJPROP_TIME, (long)tNY);
      ObjectSetInteger(0, n, OBJPROP_COLOR,       VLinNYColor);
      ObjectSetInteger(0, n, OBJPROP_WIDTH,       VLinNYGrosor);
      ObjectSetInteger(0, n, OBJPROP_STYLE,       VLinNYEstilo);
      ObjectSetInteger(0, n, OBJPROP_BACK,        true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetString(0,  n, OBJPROP_TOOLTIP,     "LBO Open — " + IntegerToString(nyOpenH) + ":00");

      // Etiqueta como OBJ_LABEL (coordenadas de pixel, independiente de temporalidad)
      string nl = VLIN_PREFIX + "NY_LBL";
      if(ObjectFind(0, nl) < 0) ObjectCreate(0, nl, OBJ_LABEL, 0, 0, 0);
      // Calcular posicion X en pixeles de tNY en el grafico actual
      int xPixel = 0;
      ChartTimePriceToXY(0, 0, tNY, 0, xPixel, xPixel); // reutilizamos xPixel para Y temporalmente
      int xPx = 0, yPx = 0;
      ChartTimePriceToXY(0, 0, tNY, SymbolInfoDouble(_Symbol, SYMBOL_BID), xPx, yPx);
      ObjectSetInteger(0, nl, OBJPROP_XDISTANCE,  xPx + 3);
      ObjectSetInteger(0, nl, OBJPROP_YDISTANCE,  20);
      ObjectSetString(0,  nl, OBJPROP_TEXT,        "LBO Open");
      ObjectSetString(0,  nl, OBJPROP_FONT,        "Consolas");
      ObjectSetInteger(0, nl, OBJPROP_FONTSIZE,    8);
      ObjectSetInteger(0, nl, OBJPROP_COLOR,       VLinNYColor);
      ObjectSetInteger(0, nl, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nl, OBJPROP_ANCHOR,      ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nl, OBJPROP_BACK,        false);
      ObjectSetInteger(0, nl, OBJPROP_SELECTABLE,  false);
   }
   else
   {
      if(ObjectFind(0, VLIN_PREFIX+"NY")      >= 0) ObjectDelete(0, VLIN_PREFIX+"NY");
      if(ObjectFind(0, VLIN_PREFIX+"NY_LBL")  >= 0) ObjectDelete(0, VLIN_PREFIX+"NY_LBL");
   }

   // Linea cierre de ventana
   if(VLinCierreVisible)
   {
      string n = VLIN_PREFIX + "CLOSE";
      if(ObjectFind(0, n) < 0)
         ObjectCreate(0, n, OBJ_VLINE, 0, (long)tCancel, (double)0);
      ObjectSetInteger(0, n, OBJPROP_TIME, (long)tCancel);
      ObjectSetInteger(0, n, OBJPROP_COLOR,       VLinCierreColor);
      ObjectSetInteger(0, n, OBJPROP_WIDTH,       VLinCierreGrosor);
      ObjectSetInteger(0, n, OBJPROP_STYLE,       VLinCierreEstilo);
      ObjectSetInteger(0, n, OBJPROP_BACK,        true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, n, OBJPROP_RAY,         false);
      ObjectSetString(0,  n, OBJPROP_TOOLTIP,     "LBO Close — " + IntegerToString(cancelHEfectivo) + ":00");

      // Etiqueta como OBJ_LABEL (coordenadas de pixel)
      string nl = VLIN_PREFIX + "CLOSE_LBL";
      if(ObjectFind(0, nl) < 0) ObjectCreate(0, nl, OBJ_LABEL, 0, 0, 0);
      int xPx = 0, yPx = 0;
      ChartTimePriceToXY(0, 0, tCancel, SymbolInfoDouble(_Symbol, SYMBOL_BID), xPx, yPx);
      ObjectSetInteger(0, nl, OBJPROP_XDISTANCE,  xPx + 3);
      ObjectSetInteger(0, nl, OBJPROP_YDISTANCE,  20);
      ObjectSetString(0,  nl, OBJPROP_TEXT,        "LBO Close");
      ObjectSetString(0,  nl, OBJPROP_FONT,        "Consolas");
      ObjectSetInteger(0, nl, OBJPROP_FONTSIZE,    8);
      ObjectSetInteger(0, nl, OBJPROP_COLOR,       VLinCierreColor);
      ObjectSetInteger(0, nl, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nl, OBJPROP_ANCHOR,      ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nl, OBJPROP_BACK,        false);
      ObjectSetInteger(0, nl, OBJPROP_SELECTABLE,  false);
   }
   else
   {
      if(ObjectFind(0, VLIN_PREFIX+"CLOSE")     >= 0) ObjectDelete(0, VLIN_PREFIX+"CLOSE");
      if(ObjectFind(0, VLIN_PREFIX+"CLOSE_LBL") >= 0) ObjectDelete(0, VLIN_PREFIX+"CLOSE_LBL");
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ELIMINAR LINEAS VERTICALES                                       |
//+------------------------------------------------------------------+
void VLinEliminar()
{
   ObjectsDeleteAll(0, VLIN_PREFIX);
   ChartRedraw(0);
}

#define RANGO_PREFIX "RRL_RANGO_"

//+------------------------------------------------------------------+
//| DIBUJAR MARCO DEL RANGO DE LONDRES                               |
//+------------------------------------------------------------------+
void RangoDisbujar()
{
   if(!RangoVisible || !rangeSet || rangeHigh <= 0 || rangeLow <= 0) return;

   // Calcular tiempos exactos de la sesion de Londres
   // Buscar la barra M1 mas cercana al inicio y fin de Londres del dia actual
   datetime ahora = TimeCurrent();
   MqlDateTime dtA;
   TimeToStruct(ahora, dtA);
   datetime inicioDia = ahora - dtA.hour * 3600 - dtA.min * 60 - dtA.sec;

   datetime tInicio = inicioDia + londonStartH * 3600 + londonStartM * 60;
   datetime tFin    = inicioDia + londonEndH   * 3600 + londonEndM   * 60 + 59;

   // Ajuste medianoche: si tFin queda antes de tInicio (cruce de dia)
   if(tFin < tInicio) tFin += 86400;

   // Calcular color de relleno con opacidad simulada
   int   opac  = MathMax(1, MathMin(100, RangoOpacidad));
   uchar r_rel = (uchar)((RangoColorRelleno >> 16) & 0xFF);
   uchar g_rel = (uchar)((RangoColorRelleno >> 8)  & 0xFF);
   uchar b_rel = (uchar)( RangoColorRelleno         & 0xFF);
   double factor = opac / 100.0;
   uchar  r_f = (uchar)(r_rel * factor + 255 * (1 - factor));
   uchar  g_f = (uchar)(g_rel * factor + 255 * (1 - factor));
   uchar  b_f = (uchar)(b_rel * factor + 255 * (1 - factor));
   color  clrRelleno = (color)((r_f << 16) | (g_f << 8) | b_f);

   // ── Relleno (rectangulo base, debajo del marco) ──────────────────
   string nFill = RANGO_PREFIX + "FILL";
   if(RangoRelleno)
   {
      if(ObjectFind(0, nFill) < 0)
         ObjectCreate(0, nFill, OBJ_RECTANGLE, 0, (long)tInicio, (double)rangeHigh, (long)tFin, (double)rangeLow);
      ObjectSetInteger(0, nFill, OBJPROP_TIME, 0, (long)tInicio);
      ObjectSetDouble(0, nFill, OBJPROP_PRICE, 0, rangeHigh);
      ObjectSetInteger(0, nFill, OBJPROP_TIME, 1, (long)tFin);
      ObjectSetDouble(0, nFill, OBJPROP_PRICE, 1, rangeLow);
      ObjectSetInteger(0, nFill, OBJPROP_COLOR,       clrRelleno);
      ObjectSetInteger(0, nFill, OBJPROP_BGCOLOR,     clrRelleno);
      ObjectSetInteger(0, nFill, OBJPROP_FILL,        true);
      ObjectSetInteger(0, nFill, OBJPROP_WIDTH,       1);
      ObjectSetInteger(0, nFill, OBJPROP_STYLE,       STYLE_SOLID);
      ObjectSetInteger(0, nFill, OBJPROP_BACK,        true);
      ObjectSetInteger(0, nFill, OBJPROP_SELECTABLE,  false);
      ObjectSetString(0,  nFill, OBJPROP_TOOLTIP,     "Rango Londres");
   }
   else
   {
      if(ObjectFind(0, nFill) >= 0) ObjectDelete(0, nFill);
   }

   // ── Marco: 4 lados como segmentos OBJ_TREND ─────────────────────
   // Superior
   string nTop = RANGO_PREFIX + "TOP";
   if(ObjectFind(0, nTop) < 0)
      ObjectCreate(0, nTop, OBJ_TREND, 0, (long)tInicio, (double)rangeHigh, (long)tFin, (double)rangeHigh);
   ObjectSetInteger(0, nTop, OBJPROP_TIME, 0, (long)tInicio);
   ObjectSetDouble(0, nTop, OBJPROP_PRICE, 0, rangeHigh);
   ObjectSetInteger(0, nTop, OBJPROP_TIME, 1, (long)tFin);
   ObjectSetDouble(0, nTop, OBJPROP_PRICE, 1, rangeHigh);
   ObjectSetInteger(0, nTop, OBJPROP_COLOR,      RangoColorLinea);
   ObjectSetInteger(0, nTop, OBJPROP_WIDTH,      RangoGrosor);
   ObjectSetInteger(0, nTop, OBJPROP_STYLE,      RangoEstilo);
   ObjectSetInteger(0, nTop, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nTop, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, nTop, OBJPROP_BACK,       true);
   ObjectSetInteger(0, nTop, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  nTop, OBJPROP_TOOLTIP,    "Rango Londres — Alto: " + DoubleToString(rangeHigh, symDigits));

   // Inferior
   string nBot = RANGO_PREFIX + "BOT";
   if(ObjectFind(0, nBot) < 0)
      ObjectCreate(0, nBot, OBJ_TREND, 0, (long)tInicio, (double)rangeLow, (long)tFin, (double)rangeLow);
   ObjectSetInteger(0, nBot, OBJPROP_TIME, 0, (long)tInicio);
   ObjectSetDouble(0, nBot, OBJPROP_PRICE, 0, rangeLow);
   ObjectSetInteger(0, nBot, OBJPROP_TIME, 1, (long)tFin);
   ObjectSetDouble(0, nBot, OBJPROP_PRICE, 1, rangeLow);
   ObjectSetInteger(0, nBot, OBJPROP_COLOR,      RangoColorLinea);
   ObjectSetInteger(0, nBot, OBJPROP_WIDTH,      RangoGrosor);
   ObjectSetInteger(0, nBot, OBJPROP_STYLE,      RangoEstilo);
   ObjectSetInteger(0, nBot, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nBot, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, nBot, OBJPROP_BACK,       true);
   ObjectSetInteger(0, nBot, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  nBot, OBJPROP_TOOLTIP,    "Rango Londres — Bajo: " + DoubleToString(rangeLow, symDigits));

   // Izquierdo
   string nLft = RANGO_PREFIX + "LFT";
   if(ObjectFind(0, nLft) < 0)
      ObjectCreate(0, nLft, OBJ_TREND, 0, (long)tInicio, (double)rangeHigh, (long)tInicio, (double)rangeLow);
   ObjectSetInteger(0, nLft, OBJPROP_TIME, 0, (long)tInicio);
   ObjectSetDouble(0, nLft, OBJPROP_PRICE, 0, rangeHigh);
   ObjectSetInteger(0, nLft, OBJPROP_TIME, 1, (long)tInicio);
   ObjectSetDouble(0, nLft, OBJPROP_PRICE, 1, rangeLow);
   ObjectSetInteger(0, nLft, OBJPROP_COLOR,      RangoColorLinea);
   ObjectSetInteger(0, nLft, OBJPROP_WIDTH,      RangoGrosor);
   ObjectSetInteger(0, nLft, OBJPROP_STYLE,      RangoEstilo);
   ObjectSetInteger(0, nLft, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nLft, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, nLft, OBJPROP_BACK,       true);
   ObjectSetInteger(0, nLft, OBJPROP_SELECTABLE, false);

   // Derecho
   string nRgt = RANGO_PREFIX + "RGT";
   if(ObjectFind(0, nRgt) < 0)
      ObjectCreate(0, nRgt, OBJ_TREND, 0, (long)tFin, (double)rangeHigh, (long)tFin, (double)rangeLow);
   ObjectSetInteger(0, nRgt, OBJPROP_TIME, 0, (long)tFin);
   ObjectSetDouble(0, nRgt, OBJPROP_PRICE, 0, rangeHigh);
   ObjectSetInteger(0, nRgt, OBJPROP_TIME, 1, (long)tFin);
   ObjectSetDouble(0, nRgt, OBJPROP_PRICE, 1, rangeLow);
   ObjectSetInteger(0, nRgt, OBJPROP_COLOR,      RangoColorLinea);
   ObjectSetInteger(0, nRgt, OBJPROP_WIDTH,      RangoGrosor);
   ObjectSetInteger(0, nRgt, OBJPROP_STYLE,      RangoEstilo);
   ObjectSetInteger(0, nRgt, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nRgt, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, nRgt, OBJPROP_BACK,       true);
   ObjectSetInteger(0, nRgt, OBJPROP_SELECTABLE, false);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ELIMINAR MARCO DEL RANGO                                         |
//+------------------------------------------------------------------+
void RangoEliminar()
{
   ObjectsDeleteAll(0, RANGO_PREFIX);
   ChartRedraw(0);
}

#define PANEL_PREFIX "RRL_"

color CLR_BG      = C'18,20,32';
color CLR_BORDER  = C'55,60,85';
color CLR_TITLE   = C'255,200,0';
color CLR_HEADER  = C'130,170,255';
color CLR_TEXT    = C'210,210,210';
color CLR_GREEN   = C'70,210,110';
color CLR_RED     = C'255,75,75';
color CLR_YELLOW  = C'255,215,50';
color CLR_GRAY    = C'110,115,135';
color CLR_WHITE   = C'245,245,245';

int PX      = 10;
int PY      = 25;
int PW      = 238;
int RH      = 16;
int FS      = 8;
int pRow    = 0;

//+------------------------------------------------------------------+
//| SINCRONIZAR PARAMETROS DEL DASHBOARD CON VARIABLES INTERNAS     |
//+------------------------------------------------------------------+
void SyncDashParams()
{
   CLR_BG     = DashClrFondo;
   CLR_BORDER = DashClrBorde;
   CLR_TITLE  = DashClrTitulo;
   CLR_HEADER = DashClrSeccion;
   CLR_TEXT   = DashClrTexto;
   CLR_WHITE  = DashClrValor;
   CLR_GREEN  = DashClrVerde;
   CLR_RED    = DashClrRojo;
   CLR_YELLOW = DashClrAmarillo;
   CLR_GRAY   = DashClrGris;
   PX = DashPosX;
   PY = DashPosY;
   PW = DashAncho;
   RH = DashAltoFila;
   FS = DashTamano;
}

void _Btn(string id, string txt, int x, int y, int w, color bg, color tc)
{
   string nm = PANEL_PREFIX + "BTN_" + id;
   if(ObjectFind(0,nm) < 0) ObjectCreate(0,nm,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,       w);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,       RH-1);
   ObjectSetString(0,nm,OBJPROP_TEXT,         txt);
   ObjectSetString(0,nm,OBJPROP_FONT,         DashFuente);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,    FS);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,       tc);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,tc);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_BACK,        false);
   ObjectSetInteger(0,nm,OBJPROP_STATE,       false); // no presionado por defecto
}

void _Rect(string n, int x, int y, int w, int h, color bg, color bc)
{
   string nm = PANEL_PREFIX+n;
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,bc);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_BACK,false); // false = por encima del grafico
   // El fondo es seleccionable para permitir arrastre con el mouse
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE, StringFind(n,"BG")>=0 ? true : false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,   false);
}

void _Lbl(string n, string txt, int x, int y, color clr, int fs=0)
{
   string nm = PANEL_PREFIX+n;
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
   ObjectSetString(0,nm,OBJPROP_FONT,DashFuente);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs>0?fs:FS);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_BACK,false);
}

void _Row(string id, string lbl, string val, color lc, color vc)
{
   int y = PY+4+pRow*RH;
   _Lbl("L"+id, lbl, PX+6,     y, lc);
   _Lbl("V"+id, val, PX+6+115, y, vc);
   pRow++;
}

void _Hdr(string id, string title)
{
   int y = PY+4+pRow*RH;
   _Rect("S"+id, PX+2, y-1, PW-4, RH-1, C'30,32,48', CLR_BORDER);
   _Lbl("H"+id, title, PX+6, y, CLR_HEADER, FS);
   pRow++;
}

string _HM(int mins)
{
   return StringFormat("%02d:%02d", mins/60, mins%60);
}

string _CK(bool v) { return v ? "OK " : "-- "; }

string _BalaTxt(int i)
{
   if(balaActual <= i && !balas[i].active) return "[---]";
   if(balas[i].active)                     return "[ACT]";
   if(balas[i].resultado == "TP")          return "[ TP]";
   if(balas[i].resultado == "SP")          return "[ SP]";
   if(balas[i].resultado == "BE")          return "[ BE]";
   if(balas[i].resultado == "SL")          return "[ SL]";
   return                                         "[---]";
}

color _BalaClr(int i)
{
   if(balaActual <= i && !balas[i].active) return CLR_GRAY;
   if(balas[i].active)                     return CLR_YELLOW;
   if(balas[i].resultado == "TP")          return CLR_GREEN;
   if(balas[i].resultado == "SP")          return C'100,200,255'; // azul claro
   if(balas[i].resultado == "BE")          return C'160,160,160'; // gris claro
   if(balas[i].resultado == "SL")          return CLR_RED;
   return CLR_GRAY;
}

string _Fase(int now, int ls, int le, int ny, int ct, int cl)
{
   if(now >= cl)            return "CERRADO";
   if(now >= ct)            return "FIN VENTANA";
   if(now >= ny && now < ct) return "VENTANA NY  ";
   if(now >= ls && now <= le) return "RANGO LDN  ";
   return                          "PRE-SESION ";
}

//+------------------------------------------------------------------+
//| ACTUALIZAR PANEL                                                 |
//+------------------------------------------------------------------+
void PanelUpdate()
{
   if(!DashVisible) { PanelDestroy(); return; }
   SyncDashParams(); // Aplicar cambios de parametros en tiempo real
   pRow = 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int now = dt.hour*60+dt.min;
   int ls  = londonStartH*60+londonStartM;
   int le  = londonEndH*60+londonEndM;

   int ny  = nyOpenH*60;
   int ct  = cancelH*60;
   int cl  = closeAllH*60;

   // Los viernes ajustar cancelTime igual que en OnTick
   if(dt.day_of_week == 5 && VentanaViernesPips < 4)
      ct = ny + VentanaViernesPips * 60;
   // Los viernes closeTime = CierreViernesBroker (si esta activo)
   if(dt.day_of_week == 5 && CierreViernesBroker >= 0)
      cl = CierreViernesBroker * 60;

   // Horas para mostrar en panel (sin ajuste de medianoche)
   int ct_disp = ct;
   int cl_disp = cl;

   if(cl <= ny)  cl += 1440;
   if(ct <= ny)  ct += 1440;
   int nowAdj = (cl > 1440 && now < ny) ? now + 1440 : now;

   // Altura dinamica basada en contenido real:
   // titulo(1) + cuenta(1hdr+2) + horarios(1hdr+1modo+3horas+1fase+1countdown)
   // + DST(2 si auto) + rango(1hdr+1) + balas(1hdr+3+1visual) + pnl(1hdr+3) = 22 (+2 DST)
   int filasBase  = 23 + (UsarDSTAutomatico ? 2 : 0); // +1 fila por segunda fila de balas (B5-B8)
   int filasBala  = 0;
   int nRows = panelMinimizado ? 1 : filasBase + filasBala;
   _Rect("BG", PX, PY, PW, nRows*RH+14, CLR_BG, CLR_BORDER);

   // TITULO + BOTONES
   string estadoBot = botPausado      ? "PAUSADO"     :
                      esFestivoHoyUS  ? "FESTIVO US"  :
                      esFestivoHoyUK  ? "FESTIVO UK"  :
                      tpDiarioAlcanzado ? "TP DIA"    :
                      balaEnCurso     ? "EN CURSO"    :
                      (!PuedeLanzarBala() ? "AGOTADO" : "EN ESPERA");
   color cEst = botPausado                               ? CLR_YELLOW :
                (esFestivoHoyUS || esFestivoHoyUK)       ? CLR_RED    :
                tpDiarioAlcanzado                        ? CLR_GREEN  :
                balaEnCurso                              ? CLR_GREEN  :
                (!PuedeLanzarBala()) ? CLR_RED : CLR_GREEN;
   _Lbl("TTL",  "  BOT RRL US30", PX+6,  PY+4, CLR_TITLE, 9);
   _Lbl("TTLS", estadoBot,        PX+130, PY+4, cEst, 9);

   // Boton minimizar (esquina derecha del titulo)
   string minTxt = panelMinimizado ? "[+]" : "[-]";
   _Btn("MIN", minTxt, PX+PW-28, PY+2, 24, CLR_BG, CLR_GRAY);

   // Boton pausa (junto al minimizar)
   string pausaTxt = botPausado ? "[>]" : "[|]";
   color  pausaClr = botPausado ? CLR_YELLOW : CLR_GRAY;
   _Btn("PAUSE", pausaTxt, PX+PW-54, PY+2, 24, CLR_BG, pausaClr);

   pRow++;

   // Si minimizado: ocultar todos los textos excepto titulo y botones
   if(panelMinimizado)
   {
      // Eliminar todos los objetos del panel excepto fondo, titulo y botones
      int total = ObjectsTotal(0);
      for(int i = total-1; i >= 0; i--)
      {
         string nm = ObjectName(0, i);
         if(StringFind(nm, PANEL_PREFIX) != 0) continue;
         // Conservar: BG (fondo), TTL/TTLS (titulo), BTN_ (botones)
         if(nm == PANEL_PREFIX+"BG")    continue;
         if(nm == PANEL_PREFIX+"TTL")   continue;
         if(nm == PANEL_PREFIX+"TTLS")  continue;
         if(StringFind(nm, PANEL_PREFIX+"BTN_") == 0) continue;
         ObjectDelete(0, nm);
      }
      ChartRedraw(0);
      return;
   }

   // CUENTA
   _Hdr("ACC","-- CUENTA --");
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   _Row("BA","Balance", "$"+DoubleToString(bal,2), CLR_TEXT, CLR_WHITE);
   _Row("EQ","Equity",  "$"+DoubleToString(eq, 2), CLR_TEXT, eq>=bal?CLR_GREEN:CLR_RED);

   // HORARIOS
   _Hdr("HOR","-- HORARIOS (broker) --");
   string modoHz = UsarDSTAutomatico
                   ? "AUTO DST GMT+" + IntegerToString(brokerOffsetHours)
                   : "MANUAL  GMT+" + IntegerToString(brokerOffsetHours);
   color  cModo  = UsarDSTAutomatico ? CLR_GREEN : CLR_YELLOW;
   _Row("HM","Modo", modoHz, CLR_TEXT, cModo);
   if(UsarDSTAutomatico)
   {
      string gmtLdn = EsBST(TimeGMT()) ? "GMT+1 BST" : "GMT+0";
      string gmtNYs = EsEDT(TimeGMT()) ? "GMT-4 EDT" : "GMT-5 EST";
      _Row("HG1","Londres", gmtLdn, CLR_TEXT, CLR_GRAY);
      _Row("HG2","NY",      gmtNYs, CLR_TEXT, CLR_GRAY);
   }
   _Row("H1","Londres", _HM(ls)+" - "+_HM(le),         CLR_TEXT, CLR_GRAY);
   _Row("H2","NY Open", _HM(ny)+" - "+_HM(ct_disp),    CLR_TEXT, CLR_GRAY);
   _Row("H3","Cierre",  _HM(cl_disp),                   CLR_TEXT, CLR_GRAY);
   string fase = _Fase(nowAdj,ls,le,ny,ct,cl);
   color cFase = (fase=="VENTANA NY  ") ? CLR_GREEN :
                 (fase=="RANGO LDN  ") ? CLR_YELLOW :
                 (fase=="CERRADO")      ? CLR_RED : CLR_GRAY;
   _Row("H4","Fase", fase, CLR_TEXT, cFase);

   // Cuenta regresiva al siguiente evento
   string cuentaTxt  = "";
   string cuentaLabel= "";
   color  cuentaClr  = CLR_GRAY;
   int    minRestante = 0;

   if(nowAdj < ls)
   {
      minRestante  = ls - nowAdj;
      cuentaLabel  = "Rango en";
      cuentaClr    = CLR_GRAY;
   }
   else if(nowAdj >= ls && nowAdj <= le)
   {
      minRestante  = ny - nowAdj;
      cuentaLabel  = "NY Open en";
      cuentaClr    = CLR_YELLOW;
   }
   else if(nowAdj > le && nowAdj < ny)
   {
      minRestante  = ny - nowAdj;
      cuentaLabel  = "NY Open en";
      cuentaClr    = CLR_YELLOW;
   }
   else if(nowAdj >= ny && nowAdj < ct)
   {
      minRestante  = ct - nowAdj;
      cuentaLabel  = "Cierre vent.";
      cuentaClr    = CLR_GREEN;
   }
   else if(nowAdj >= ct && nowAdj < cl)
   {
      minRestante  = cl - nowAdj;
      cuentaLabel  = "Cierre NY en";
      cuentaClr    = CLR_GRAY;
   }
   else
   {
      cuentaLabel  = "Mercado";
      cuentaTxt    = "CERRADO";
      cuentaClr    = CLR_RED;
   }

   if(cuentaTxt == "" && minRestante > 0)
   {
      int hh = minRestante / 60;
      int mm = minRestante % 60;
      cuentaTxt = (hh > 0 ? IntegerToString(hh)+"h " : "") +
                  StringFormat("%02d", mm) + "m";
   }
   _Row("H5", cuentaLabel, cuentaTxt, CLR_TEXT, cuentaClr);

   // RANGO
   _Hdr("RNG","-- RANGO LONDRES --");
   string rngTxt = rangeSet
                   ? DoubleToString((rangeHigh-rangeLow)/pipSize,1)+" pips"
                   : "Calculando...";
   _Row("RP","Pips", rngTxt, CLR_TEXT, rangeSet ? CLR_WHITE : CLR_GRAY);

   // BALAS
   _Hdr("BLS","-- BALAS --");
   int balasReales  = ContarBalasHoy();
   int totalMax     = GetTotalBalasMax();
   int balasRest    = GetBalasRestantes();
   double presup    = GetPresupuestoRestantePct();
   // Fila 1: balas fisicas lanzadas vs total del dia
   color cLanzadas  = balasRest > 0 ? CLR_GREEN : CLR_RED;
   _Row("BL1","Balas",
        IntegerToString(balasReales) + " / " + IntegerToString(totalMax),
        CLR_TEXT, cLanzadas);
   // Fila 2: presupuesto de riesgo restante
   color cPresup = presup > RiskPerBala*2 ? CLR_GREEN :
                   presup > 0             ? CLR_YELLOW : CLR_RED;
   _Row("BL3","Presupuesto",
        DoubleToString(presup,2) + "% / " + DoubleToString(MaxDailyLossPct,1) + "%",
        CLR_TEXT, cPresup);
   // Fila 3: resultados por tipo
   _Row("BL2","Resultados",
        IntegerToString(balasConTP)+"TP "        +IntegerToString(balasConSP)+"SP "        +IntegerToString(balasConBE)+"BE "        +IntegerToString(balasConSL)+"SL",
        CLR_GREEN, CLR_RED);
   // Dos filas de 4 balas cada una (B1-B4 y B5-B8)
   int totalBalasMax = GetTotalBalasMax();
   int wBala = (PW - 12) / 4; // ancho por bala segun panel
   int yb1 = PY+4+pRow*RH;
   for(int i=0;i<4;i++)
      _Lbl("BX"+IntegerToString(i),
           "B"+IntegerToString(i+1)+_BalaTxt(i),
           PX+6+i*wBala, yb1, _BalaClr(i));
   pRow++;
   int yb2 = PY+4+pRow*RH;
   for(int i=4;i<8;i++)
      _Lbl("BX"+IntegerToString(i),
           "B"+IntegerToString(i+1)+_BalaTxt(i),
           PX+6+(i-4)*wBala, yb2, _BalaClr(i));
   pRow++;

   _Hdr("PNL","-- PnL DIA --");
   double pnlNeto  = GetPnLNetoDiarioPct();
   double pnlUSD   = balanceInicioDia > 0 ? balanceInicioDia * pnlNeto / 100.0 : 0;
   double margen   = MaxDailyLossPct + pnlNeto;
   color cPnl      = pnlNeto >= 0 ? CLR_GREEN : CLR_RED;
   color cMrg      = margen > RiskPerBala*2 ? CLR_GREEN :
                     margen > RiskPerBala   ? CLR_YELLOW : CLR_RED;
   _Row("PN1","Neto %", (pnlNeto>=0?"+":"")+DoubleToString(pnlNeto,2)+"%", CLR_TEXT, cPnl);
   _Row("PN3","Neto $", (pnlUSD>=0?"+$":"-$")+DoubleToString(MathAbs(pnlUSD),2), CLR_TEXT, cPnl);
   _Row("PN2","Margen", DoubleToString(margen,2)+"% / "+DoubleToString(MaxDailyLossPct,1)+"%", CLR_TEXT, cMrg);

   // Redibujar etiquetas de lineas verticales para mantener posicion correcta
   if(VLinNYVisible || VLinCierreVisible) VLinDisbujar();

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| DESTRUIR PANEL                                                   |
//+------------------------------------------------------------------+
void PanelDestroy()
{
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//|               ESTADISTICAS DIARIAS EN CSV                        |
//+------------------------------------------------------------------+
//  Archivo: MQL5/Files/RRL_US30_Stats.csv                          
//  Una fila por dia operado                                         
//  Columnas:                                                        
//    Fecha, Dia, Balance_Inicio, Balance_Fin, PnL_USD, PnL_Pct,    
//    Balas_Total, Balas_TP, Balas_SL, Rango_Pips,                  
//    CP1_Veces, TP1_Veces, CP3_Veces, TP2_Veces,                   
//    Limite_Alcanzado, Resultado                                    
//+------------------------------------------------------------------+

#define CSV_FILE "RRL_US30_Stats.csv"

//+------------------------------------------------------------------+
//| CREAR ARCHIVO CSV CON CABECERA SI NO EXISTE                      |
//+------------------------------------------------------------------+
void CSVInit()
{
   // Intentar abrir el archivo. Si no existe, crearlo con cabecera
   int handle = FileOpen(CSV_FILE, FILE_READ|FILE_CSV);
   if(handle != INVALID_HANDLE)
   {
      FileClose(handle);
      return; // Ya existe, no sobreescribir cabecera
   }

   // Crear archivo nuevo con cabecera
   handle = FileOpen(CSV_FILE, FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("CSV ERROR: No se pudo crear ", CSV_FILE, " | Error: ", GetLastError());
      return;
   }

   FileWrite(handle,
      "Fecha",
      "Dia_Semana",
      "Primera_Bala",
      "Balance_Inicio",
      "Balance_Fin",
      "PnL_USD",
      "PnL_Pct",
      "Balas_Total",
      "Balas_TP",
      "Balas_SP",
      "Balas_BE",
      "Balas_SL",
      "Rango_Pips",
      "CP1_BreakEven",
      "TP1_CierreE1",
      "CP3_SP100",
      "TP2_CierreE2",
      "Limite_Alcanzado",
      "Resultado"
   );

   FileClose(handle);
   Print("CSV creado: ", CSV_FILE);
}

//+------------------------------------------------------------------+
//| GUARDAR FILA DEL DIA EN EL CSV                                   |
//+------------------------------------------------------------------+
void CSVGuardarDia()
{
   // Solo guardar si hubo actividad (al menos una bala lanzada)
   if(balaActual == 0) return;

   double balFin    = AccountInfoDouble(ACCOUNT_BALANCE);
   double pnlUSD    = PnLCerradoDiaUSD(); // v2.66: solo deals de este EA
   double pnlPct    = balanceInicioDia > 0 ? pnlUSD / balanceInicioDia * 100.0 : 0;
   double rangePips = rangeSet ? (rangeHigh - rangeLow) / pipSize : 0;
   bool   limAlc    = GetPnLNetoDiarioPct() <= -MaxDailyLossPct;

   // Nombre del dia de la semana
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string diasSemana[] = {"Dom","Lun","Mar","Mie","Jue","Vie","Sab"};
   string diaNombre = diasSemana[dt.day_of_week];

   // Resultado del dia
   string resultado;
   if(pnlPct > 0)       resultado = "GANANCIA";
   else if(pnlPct < 0)  resultado = "PERDIDA";
   else                  resultado = "NEUTRAL";

   // Fecha en formato YYYY-MM-DD
   string fecha = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

   int handle = FileOpen(CSV_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("CSV ERROR al abrir para escribir: ", GetLastError());
      return;
   }

   // Moverse al final del archivo
   FileSeek(handle, 0, SEEK_END);

   // Hora primera bala en formato HH:MM
   string horaPB = (horaprimeraBala > 0)
                   ? TimeToString(horaprimeraBala, TIME_MINUTES)
                   : "--:--";

   FileWrite(handle,
      fecha,
      diaNombre,
      horaPB,
      DoubleToString(balanceInicioDia, 2),
      DoubleToString(balFin,           2),
      DoubleToString(pnlUSD,           2),
      DoubleToString(pnlPct,           2),
      IntegerToString(balaActual),
      IntegerToString(balasConTP),
      IntegerToString(balasConSP),
      IntegerToString(balasConBE),
      IntegerToString(balasConSL),
      DoubleToString(rangePips,        1),
      IntegerToString(statCP1),
      IntegerToString(statTP1),
      IntegerToString(statCP3),
      IntegerToString(statTP2),
      limAlc ? "SI" : "NO",
      resultado
   );

   FileClose(handle);

   Print("CSV | Dia guardado: ", fecha,
         " | PnL: ", DoubleToString(pnlPct,2), "%",
         " | Balas: ", balaActual,
         " (TP:", balasConTP, " SP:", balasConSP, " BE:", balasConBE, " SL:", balasConSL, ")",
         " | ", resultado);
}

//+------------------------------------------------------------------+
//| RESETEAR CONTADORES DE CHECKPOINTS DEL DIA                       |
//+------------------------------------------------------------------+
void CSVResetContadores()
{
   statCP1 = 0;
   statTP1 = 0;
   statCP3 = 0;
   statTP2 = 0;
}

//+------------------------------------------------------------------+
//| VERIFICAR SI ES EL ULTIMO DIA DEL MES                            |
//+------------------------------------------------------------------+
bool EsUltimoDiaMes(MqlDateTime &dt)
{
   // Dias del mes segun mes y año (considera bisiestos)
   int diasMes[13] = {0,31,28,31,30,31,30,31,31,30,31,30,31};

   // Año bisiesto: divisible por 4, excepto siglos no divisibles por 400
   bool bisiesto = (dt.year % 4 == 0 && dt.year % 100 != 0) ||
                   (dt.year % 400 == 0);
   if(bisiesto) diasMes[2] = 29;

   return dt.day == diasMes[dt.mon];
}

//+------------------------------------------------------------------+
//| GENERAR REPORTE MENSUAL LEYENDO EL CSV DIARIO                    |
//| Llamado el ultimo dia del mes despues de guardar el dia          |
//+------------------------------------------------------------------+
void CSVGenerarReporteMensual(int anio, int mes)
{
   string meses[] = {"","Enero","Febrero","Marzo","Abril","Mayo","Junio",
                     "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"};

   string prefixFecha = StringFormat("%04d-%02d", anio, mes);
   string archivoRep  = StringFormat("RRL_US30_Reporte_%04d_%02d.csv", anio, mes);

   // Leer el CSV diario y filtrar solo las filas del mes actual
   int handleLec = FileOpen(CSV_FILE, FILE_READ|FILE_CSV|FILE_ANSI);
   if(handleLec == INVALID_HANDLE)
   {
      Print("REPORTE: No se pudo leer ", CSV_FILE, " | Error: ", GetLastError());
      return;
   }

   // Acumuladores del mes
   int    diasTotales   = 0;
   int    diasGanancia  = 0;
   int    diasPerdida   = 0;
   int    diasNeutral   = 0;
   int    balasTotal    = 0;
   int    balasTP       = 0;
   int    balasSL       = 0;
   int    limitesAlc    = 0;
   int    cp1Total      = 0;
   int    tp1Total      = 0;
   int    cp3Total      = 0;
   int    tp2Total      = 0;
   double pnlUSDTotal   = 0;
   double rangeSuma     = 0;
   int    rangeDias     = 0;
   double balanceIniMes = 0;
   double balanceFinMes = 0;
   double mejorDia      = -DBL_MAX;
   double peorDia       =  DBL_MAX;
   string mejorFecha    = "";
   string peorFecha     = "";

   // Saltar cabecera
   if(!FileIsEnding(handleLec))
   {
      string cabecera = FileReadString(handleLec);
      // Si FileReadString en modo CSV lee campo a campo, avanzar hasta fin de linea
      // Detectar si leimos solo el primer campo de la cabecera
      if(cabecera == "Fecha")
      {
         // Leer el resto de campos de la cabecera
         while(!FileIsEnding(handleLec))
         {
            string campo = FileReadString(handleLec);
            if(campo == "Resultado") break; // ultimo campo de cabecera
         }
      }
   }

   // Leer cada fila campo por campo
   while(!FileIsEnding(handleLec))
   {
      string fecha    = FileReadString(handleLec);
      if(FileIsEnding(handleLec)) break;
      string diaSem   = FileReadString(handleLec);
      string horaPB   = FileReadString(handleLec); // Primera_Bala — hora, no usada en calculo
      double balIni   = StringToDouble(FileReadString(handleLec));
      double balFin   = StringToDouble(FileReadString(handleLec));
      double pnlUSD   = StringToDouble(FileReadString(handleLec));
      double pnlPct   = StringToDouble(FileReadString(handleLec));
      int numBalas    = (int)StringToInteger(FileReadString(handleLec));
      int bTP         = (int)StringToInteger(FileReadString(handleLec));
      int bSL         = (int)StringToInteger(FileReadString(handleLec));
      double rango    = StringToDouble(FileReadString(handleLec));
      int cp1         = (int)StringToInteger(FileReadString(handleLec));
      int tp1         = (int)StringToInteger(FileReadString(handleLec));
      int cp3         = (int)StringToInteger(FileReadString(handleLec));
      int tp2         = (int)StringToInteger(FileReadString(handleLec));
      string limite   = FileReadString(handleLec);
      string resultado= FileReadString(handleLec);

      // Filtrar solo filas del mes actual
      if(StringFind(fecha, prefixFecha) != 0) continue;

      diasTotales++;
      pnlUSDTotal  += pnlUSD;
      balasTotal   += numBalas;
      balasTP      += bTP;
      balasSL      += bSL;
      cp1Total     += cp1;
      tp1Total     += tp1;
      cp3Total     += cp3;
      tp2Total     += tp2;
      if(limite == "SI") limitesAlc++;
      if(resultado == "GANANCIA") diasGanancia++;
      else if(resultado == "PERDIDA") diasPerdida++;
      else diasNeutral++;
      if(rango > 0) { rangeSuma += rango; rangeDias++; }
      if(pnlPct > mejorDia) { mejorDia = pnlPct; mejorFecha = fecha; }
      if(pnlPct < peorDia)  { peorDia  = pnlPct; peorFecha  = fecha; }

      // Balance inicio y fin del mes
      if(diasTotales == 1)     balanceIniMes = balIni;
      balanceFinMes = balFin;
   }
   FileClose(handleLec);

   if(diasTotales == 0)
   {
      Print("REPORTE: Sin datos para ", prefixFecha);
      return;
   }

   // Calculos finales
   double pnlMesPct   = balanceIniMes > 0 ? (balanceFinMes - balanceIniMes) / balanceIniMes * 100.0 : 0;
   double winRateDias = diasTotales > 0 ? (double)diasGanancia / diasTotales * 100.0 : 0;
   double winRateBal  = balasTotal  > 0 ? (double)balasTP      / balasTotal  * 100.0 : 0;
   double rangePromedio = rangeDias > 0 ? rangeSuma / rangeDias : 0;

   // Escribir reporte mensual
   int handleEsc = FileOpen(archivoRep, FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(handleEsc == INVALID_HANDLE)
   {
      Print("REPORTE: No se pudo crear ", archivoRep, " | Error: ", GetLastError());
      return;
   }

   // Cabecera del reporte
   FileWrite(handleEsc, "REPORTE MENSUAL BOT RRL US30");
   FileWrite(handleEsc, "Mes", meses[mes] + " " + IntegerToString(anio));
   FileWrite(handleEsc, "Generado", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   FileWrite(handleEsc, "");

   // Resumen de cuenta
   FileWrite(handleEsc, "=== CUENTA ===");
   FileWrite(handleEsc, "Balance inicio mes", "$" + DoubleToString(balanceIniMes, 2));
   FileWrite(handleEsc, "Balance fin mes",    "$" + DoubleToString(balanceFinMes, 2));
   FileWrite(handleEsc, "PnL mes (USD)",      "$" + DoubleToString(balanceFinMes - balanceIniMes, 2));
   FileWrite(handleEsc, "PnL mes (%)",        DoubleToString(pnlMesPct, 2) + "%");
   FileWrite(handleEsc, "");

   // Resumen de operativa
   FileWrite(handleEsc, "=== OPERATIVA ===");
   FileWrite(handleEsc, "Dias operados",      IntegerToString(diasTotales));
   FileWrite(handleEsc, "Dias ganancia",      IntegerToString(diasGanancia));
   FileWrite(handleEsc, "Dias perdida",       IntegerToString(diasPerdida));
   FileWrite(handleEsc, "Dias neutral",       IntegerToString(diasNeutral));
   FileWrite(handleEsc, "Win rate dias",      DoubleToString(winRateDias, 1) + "%");
   FileWrite(handleEsc, "Dias limite alc.",   IntegerToString(limitesAlc));
   FileWrite(handleEsc, "");

   // Resumen de balas
   FileWrite(handleEsc, "=== BALAS ===");
   FileWrite(handleEsc, "Balas totales",      IntegerToString(balasTotal));
   FileWrite(handleEsc, "Balas TP",           IntegerToString(balasTP));
   FileWrite(handleEsc, "Balas SL",           IntegerToString(balasSL));
   FileWrite(handleEsc, "Win rate balas",     DoubleToString(winRateBal, 1) + "%");
   FileWrite(handleEsc, "Promedio balas/dia", DoubleToString(diasTotales > 0 ? (double)balasTotal / diasTotales : 0, 1));
   FileWrite(handleEsc, "");

   // Resumen de checkpoints
   FileWrite(handleEsc, "=== CHECKPOINTS ===");
   FileWrite(handleEsc, "CP1 Break Even",     IntegerToString(cp1Total));
   FileWrite(handleEsc, "TP1 Cierre E1",      IntegerToString(tp1Total));
   FileWrite(handleEsc, "CP3 SP+100",         IntegerToString(cp3Total));
   FileWrite(handleEsc, "TP2 Cierre E2",      IntegerToString(tp2Total));
   FileWrite(handleEsc, "");

   // Resumen del rango
   FileWrite(handleEsc, "=== RANGO LONDRES ===");
   FileWrite(handleEsc, "Promedio pips/dia",  DoubleToString(rangePromedio, 1) + " pips");
   FileWrite(handleEsc, "");

   // Mejores y peores dias
   FileWrite(handleEsc, "=== EXTREMOS ===");
   FileWrite(handleEsc, "Mejor dia",  mejorFecha + "  +" + DoubleToString(mejorDia, 2) + "%");
   FileWrite(handleEsc, "Peor dia",   peorFecha  + "   " + DoubleToString(peorDia,  2) + "%");

   FileClose(handleEsc);

   Print("============================================");
   Print(" REPORTE MENSUAL GENERADO: ", archivoRep);
   Print(" Mes: ", meses[mes], " ", anio);
   Print(" PnL mes: ", DoubleToString(pnlMesPct, 2), "%",
         " | Dias: ", diasTotales,
         " | Win rate: ", DoubleToString(winRateDias, 1), "%");
   Print(" Balas: ", balasTotal, " (TP:", balasTP, " SL:", balasSL, ")",
         " | Win balas: ", DoubleToString(winRateBal, 1), "%");
   Print("============================================");

   // Enviar resumen por Telegram
   string msgTelegram =
      "📊 <b>REPORTE MENSUAL — " + meses[mes] + " " + IntegerToString(anio) + "</b>\n" +
      "----------------\n" +
      "💵 PnL mes      : " + (pnlMesPct>=0?"+":"") + DoubleToString(pnlMesPct,2) + "%\n" +
      "📅 Dias operados: " + IntegerToString(diasTotales) + "\n" +
      "🏆 Win rate dias: " + DoubleToString(winRateDias,1) + "%\n" +
      "----------------\n" +
      "🎯 Balas totales: " + IntegerToString(balasTotal) + "\n" +
      "✅ Balas TP     : " + IntegerToString(balasTP) + "\n" +
      "❌ Balas SL     : " + IntegerToString(balasSL) + "\n" +
      "🎯 Win rate bal : " + DoubleToString(winRateBal,1) + "%\n" +
      "----------------\n" +
      "📈 Mejor dia    : " + mejorFecha + " +" + DoubleToString(mejorDia,2) + "%\n" +
      "📉 Peor dia     : " + peorFecha  + " "  + DoubleToString(peorDia, 2) + "%\n" +
      "----------------\n" +
      "💾 Guardado en  : " + archivoRep;
   TelegramSend(msgTelegram);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| EVENTO DEL GRAFICO                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      string btnPause = PANEL_PREFIX + "BTN_PAUSE";
      string btnMin   = PANEL_PREFIX + "BTN_MIN";

      if(sparam == btnPause)
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         botPausado = !botPausado;
         Print("BOT ", botPausado ? "PAUSADO." : "REANUDADO.");
         if(botPausado)
            TelegramSend("⏸ <b>BOT PAUSADO</b>\nNo se lanzaran nuevas balas hasta reanudar.");
         else
            TelegramSend("▶ <b>BOT REANUDADO</b>\nVolviendo a operar normalmente.");
         PanelUpdate();
         return;
      }

      if(sparam == btnMin)
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         panelMinimizado = !panelMinimizado;
         PanelUpdate();
         return;
      }
   }
}
//+------------------------------------------------------------------+
//  CHANGELOG
//  ---------
//
//  CONVENCION DE VERSIONES
//    v X.YZ
//    X  - Cambio mayor de arquitectura o estrategia
//    Y  - Cambio operacional (logica, parametros, calculos)
//    Z  - Cambio estetico (panel, colores, textos, comentarios)
//
//  v2.66 - Correcciones de la auditoria (ver AUDITORIA_v2.65.md)
//    - Compila: eliminada la asignacion global sin tipo de festivoAlertado
//    - Globales declarados al final del archivo movidos a la cabecera
//    - Eliminado #property strict (directiva de MQL4)
//    - ManageCheckpointsBala se ejecuta en todo momento, no solo en la ventana
//      NY: las posiciones abiertas tras cancelTime siguen con BE/SP/trailing
//    - OnInit rechaza cuentas NETTING (INIT_FAILED): E1/E2 exigen HEDGING
//    - OCO con red de seguridad: ManageCheckpointsBala cancela en cada tick las
//      stops opuestas si OnTradeTransaction no lo hizo; si llegan a abrirse
//      ambas direcciones se gestiona solo la primera y se avisa por Telegram
//    - Historial: los deals de salida por SL/TP no llevan el tag del EA, asi
//      que se asocian a su deal de entrada via DEAL_POSITION_ID. BE/SP/SL se
//      clasifican comparando precio de salida y de entrada (con tolerancia)
//    - RecuperarEstadoDesdHistorial reescrita: balaActual = bala mas alta vista
//      hoy; CP1/CP3 inferidos del SL actual con signo (antes MathAbs)
//    - Lotes: perdida por lote con OrderCalcProfit (ValorPuntoPorLote queda como
//      respaldo); paso de lote del broker; si el lote < minimo no se opera
//      (antes se subia al minimo y se excedia el riesgo)
//    - Modo de llenado segun el simbolo (SetTypeFillingBySymbol)
//    - Nuevo input ModoDSTBroker (AUTO/EUROPA/EEUU/NINGUNO). AUTO detecta el
//      offset real del servidor en vivo; en el tester aplica la regla europea
//    - Nuevo input CierreViernesBroker (antes 22:00 fijo en el codigo)
//    - Rango de Londres: velas M1 copiadas por rango de tiempo y solo CERRADAS;
//      se fija en el primer tick tras la sesion (incluye la ultima vela completa)
//      y se reintenta si el historial no esta disponible. La ventana NY exige
//      el rango definitivo (rangeFijado)
//    - PnL diario y presupuesto de riesgo solo con deals de este EA (antes el
//      balance de la cuenta: otros EAs, depositos y retiros). Comision de
//      entrada y DEAL_FEE incluidos. Nuevo input ReservaDeslizamientoPct
//    - Entrada: inputs OffsetEntradaPips, CompensarSpreadBuy (la BuyStop suma el
//      spread para que salte cuando el BID rompe) y MaxSpreadPips. Antes de
//      colocar las stops se comprueba la distancia a Ask/Bid (stops/freeze
//      level): si no cabe se espera en vez de abortar la bala. Precios
//      normalizados al tick size
//    - Telegram: cola enviada desde OnTimer (1 msg/s) en vez de WebRequest
//      sincrono dentro de OnTick; desactivado en el probador
//    - Trailing con paso minimo (input TrailingPasoPips). BE, SP y trailing
//      comprueban lado del precio, stops level y freeze level
//    - Confirmacion de reingreso: las N velas M1 cerradas MAS RECIENTES deben
//      cerrar dentro del rango (antes valia cualquier racha antigua)
//    - Bala con ordenes incompletas: si alguna ya se ejecuto, la bala se registra
//      como en curso en vez de abortarse dejando la posicion huerfana
//
//  v2.65 - Mensaje Telegram al inicio de sesion en dias festivos
//    - CanTradeToday(): al detectar festivo, si nowMin >= londonStart y
//      festivoAlertado=false, envia mensaje "DIA NO OPERATIVO" con nombre
//      del festivo, fecha, horarios de Londres y NY
//    - GetNombreFestivo(): nueva funcion que retorna el nombre legible del
//      festivo activo (US o UK) basado en los flags esFestivoHoyUS/UK
//    - festivoAlertado: nuevo flag global, se resetea en ResetDaily
//    - El mensaje llega una sola vez por dia al inicio de la sesion de Londres
//
//  v2.64 - Mensaje "Rango fijado" solo en tiempo real
//    - Eliminado TelegramSend del bloque de reconstruccion retroactiva en OnInit
//    - El mensaje solo se envia en OnTick al cierre real de la sesion de Londres
//    - Evita mensajes duplicados o confusos al reiniciar el EA despues de las 15:59
//    - La reconstruccion del rango y el Print en Journal se mantienen intactos
//
//  v2.63 - Fix CSV diario: columnas Balas_SP y Balas_BE
//    - CSVInit: cabecera ahora incluye Balas_SP y Balas_BE entre Balas_TP y Balas_SL
//    - CSVGuardarDia: FileWrite ahora incluye balasConSP y balasConBE
//    - El Print de diagnostico ya los mostraba correctamente desde v2.50 pero
//      las columnas del archivo CSV no coincidian con los datos reales
//
//  v2.62 - Fix reset del viernes
//    - closeTime los viernes ajustado a 22:00 (cierre real del mercado US30)
//      Antes: closeTime = 23:00 pero el mercado cierra a 22:00 → no hay ticks
//      → el reset nunca se ejecutaba → el lunes arrancaba con datos del viernes
//    - OnInit: si currentDay != dia actual al arrancar, se ejecuta ResetDaily()
//      antes de recuperar el estado (cubre el caso lunes tras fin de semana)
//    - PanelUpdate y VLinDisbujar actualizados para reflejar 22:00 los viernes

//+------------------------------------------------------------------+
