//+------------------------------------------------------------------+
//|                                                   SB_NYClock.mqh |
//|  Conversión hora servidor <-> UTC <-> Nueva York con DST exacto. |
//|                                                                  |
//|  Fuente de verdad = MODELO (offset invierno + regla DST broker), |
//|  porque en el Strategy Tester TimeGMT()==TimeTradeServer().      |
//|  En vivo se contrasta con TimeGMT(); en tester/histórico se      |
//|  contrasta con la hora de apertura semanal (dom. 17:00 NY).      |
//+------------------------------------------------------------------+
#ifndef SB_NYCLOCK_MQH
#define SB_NYCLOCK_MQH

#include "SB_Defines.mqh"

class CNYClock
  {
private:
   int               m_stdOffset;     // offset de invierno del broker (segundos)
   ENUM_BROKER_DST   m_dstRule;
   //--- caché anual de transiciones DST (en UTC)
   int               m_cacheYear;
   datetime          m_usStart,m_usEnd,m_euStart,m_euEnd;
   //--- caché diaria
   datetime          m_nyDay;         // 00:00 NY del día actual, expresado en "reloj NY"
   bool              m_wOn[SB_MAX_WIN];
   int               m_wStartMin[SB_MAX_WIN];
   int               m_wEndMin[SB_MAX_WIN];
   datetime          m_wStartSrv[SB_MAX_WIN];
   datetime          m_wEndSrv[SB_MAX_WIN];

   static datetime   NthSunday(const int year,const int mon,const int n);
   static datetime   LastSunday(const int year,const int mon);
   void              EnsureYear(const datetime utc);
   bool              IsUSDST(const datetime utc);
   bool              IsEUDST(const datetime utc);

public:
                     CNYClock(void);
   void              Init(const int stdOffsetHours,const ENUM_BROKER_DST rule);
   void              SetWindow(const int idx,const bool on,const int startMinNY,const int endMinNY);

   int               BrokerOffsetFromUTC(const datetime utc);
   datetime          ServerToUTC(const datetime srv);
   datetime          UTCToNY(const datetime utc);
   datetime          ServerToNY(const datetime srv);
   datetime          NYToServer(const datetime ny);

   bool              RefreshDay(const datetime srv);       // true si cambió el día NY
   datetime          NYDay(void) const { return m_nyDay; }
   datetime          NYMidnightServer(void) { return NYToServer(m_nyDay); }

   int               WindowAt(const datetime srv,const int leadSec) const;
   bool              InWindow(const int idx,const datetime srv) const;
   datetime          WindowStart(const int idx) const { return (idx>=0 && idx<SB_MAX_WIN)?m_wStartSrv[idx]:0; }
   datetime          WindowEnd(const int idx)   const { return (idx>=0 && idx<SB_MAX_WIN)?m_wEndSrv[idx]:0;   }
   string            WindowName(const int idx) const;

   bool              ValidateLive(void);
   int               ValidateHistory(const int maxBars=9000);
  };

//+------------------------------------------------------------------+
CNYClock::CNYClock(void) : m_stdOffset(7200),m_dstRule(BROKER_DST_US),
                           m_cacheYear(0),m_usStart(0),m_usEnd(0),m_euStart(0),m_euEnd(0),
                           m_nyDay(0)
  {
   for(int i=0;i<SB_MAX_WIN;i++)
     {
      m_wOn[i]=false; m_wStartMin[i]=0; m_wEndMin[i]=0;
      m_wStartSrv[i]=0; m_wEndSrv[i]=0;
     }
  }

//+------------------------------------------------------------------+
void CNYClock::Init(const int stdOffsetHours,const ENUM_BROKER_DST rule)
  {
   m_stdOffset=stdOffsetHours*3600;
   m_dstRule  =rule;
   m_cacheYear=0;
   m_nyDay    =0;
  }

//+------------------------------------------------------------------+
void CNYClock::SetWindow(const int idx,const bool on,const int startMinNY,const int endMinNY)
  {
   if(idx<0 || idx>=SB_MAX_WIN) return;
   m_wOn[idx]=on; m_wStartMin[idx]=startMinNY; m_wEndMin[idx]=endMinNY;
   m_nyDay=0;                                   // forzar recálculo
  }

//+------------------------------------------------------------------+
//| N-ésimo domingo del mes (00:00 de ese día)                       |
//+------------------------------------------------------------------+
datetime CNYClock::NthSunday(const int year,const int mon,const int n)
  {
   MqlDateTime s; ZeroMemory(s);
   s.year=year; s.mon=mon; s.day=1;
   datetime first=StructToTime(s);
   TimeToStruct(first,s);                        // rellena day_of_week (0 = domingo)
   int toSunday=(7-s.day_of_week)%7;
   return first+(datetime)((toSunday+7*(n-1))*86400);
  }

//+------------------------------------------------------------------+
//| Último domingo del mes (00:00 de ese día)                        |
//+------------------------------------------------------------------+
datetime CNYClock::LastSunday(const int year,const int mon)
  {
   MqlDateTime s; ZeroMemory(s);
   s.year=(mon==12)?year+1:year;
   s.mon =(mon==12)?1:mon+1;
   s.day =1;
   datetime last=StructToTime(s)-86400;          // último día del mes
   TimeToStruct(last,s);
   return last-(datetime)(s.day_of_week*86400);
  }

//+------------------------------------------------------------------+
void CNYClock::EnsureYear(const datetime utc)
  {
   MqlDateTime s; TimeToStruct(utc,s);
   if(s.year==m_cacheYear) return;
   m_cacheYear=s.year;
   m_usStart=NthSunday(s.year,3,2) +7*3600;     // 02:00 EST  = 07:00 UTC
   m_usEnd  =NthSunday(s.year,11,1)+6*3600;     // 02:00 EDT  = 06:00 UTC
   m_euStart=LastSunday(s.year,3)  +1*3600;     // 01:00 UTC
   m_euEnd  =LastSunday(s.year,10) +1*3600;     // 01:00 UTC
  }

bool CNYClock::IsUSDST(const datetime utc) { EnsureYear(utc); return(utc>=m_usStart && utc<m_usEnd); }
bool CNYClock::IsEUDST(const datetime utc) { EnsureYear(utc); return(utc>=m_euStart && utc<m_euEnd); }

//+------------------------------------------------------------------+
int CNYClock::BrokerOffsetFromUTC(const datetime utc)
  {
   bool dst=(m_dstRule==BROKER_DST_US && IsUSDST(utc)) ||
            (m_dstRule==BROKER_DST_EU && IsEUDST(utc));
   return m_stdOffset+(dst?3600:0);
  }

//+------------------------------------------------------------------+
//| La ambigüedad de 1h en la transición cae en domingo de madrugada |
//| con el mercado FX cerrado, por lo que es irrelevante.            |
//+------------------------------------------------------------------+
datetime CNYClock::ServerToUTC(const datetime srv) { return srv-BrokerOffsetFromUTC(srv-m_stdOffset); }
datetime CNYClock::UTCToNY(const datetime utc)     { return utc-(IsUSDST(utc)?4:5)*3600; }
datetime CNYClock::ServerToNY(const datetime srv)  { return UTCToNY(ServerToUTC(srv)); }

datetime CNYClock::NYToServer(const datetime ny)
  {
   datetime utc=ny+5*3600;                       // hipótesis EST
   if(IsUSDST(utc)) utc=ny+4*3600;              // corregir a EDT
   return utc+BrokerOffsetFromUTC(utc);
  }

//+------------------------------------------------------------------+
//| Recalcula las ventanas en hora servidor solo al cambiar el día NY|
//+------------------------------------------------------------------+
bool CNYClock::RefreshDay(const datetime srv)
  {
   datetime ny=ServerToNY(srv);
   datetime nyMidnight=(datetime)(ny-(ny%86400));
   if(nyMidnight==m_nyDay) return false;
   m_nyDay=nyMidnight;
   for(int i=0;i<SB_MAX_WIN;i++)
     {
      m_wStartSrv[i]=NYToServer(nyMidnight+m_wStartMin[i]*60);
      m_wEndSrv[i]  =NYToServer(nyMidnight+m_wEndMin[i]*60);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Índice de la ventana activa (incluye margen previo 'leadSec')    |
//+------------------------------------------------------------------+
int CNYClock::WindowAt(const datetime srv,const int leadSec) const
  {
   for(int i=0;i<SB_MAX_WIN;i++)
      if(m_wOn[i] && srv>=m_wStartSrv[i]-leadSec && srv<m_wEndSrv[i])
         return i;
   return -1;
  }

bool CNYClock::InWindow(const int idx,const datetime srv) const
  {
   if(idx<0 || idx>=SB_MAX_WIN) return false;
   return(srv>=m_wStartSrv[idx] && srv<m_wEndSrv[idx]);
  }

string CNYClock::WindowName(const int idx) const
  {
   if(idx<0 || idx>=SB_MAX_WIN) return "-";
   return StringFormat("%02d-%02dNY",m_wStartMin[idx]/60,m_wEndMin[idx]/60);
  }

//+------------------------------------------------------------------+
//| En vivo: contrastar modelo con TimeTradeServer()-TimeGMT()       |
//+------------------------------------------------------------------+
bool CNYClock::ValidateLive(void)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return true;
   long diff    =(long)TimeTradeServer()-(long)TimeGMT();
   long measured=(long)(MathRound((double)diff/1800.0)*1800.0);
   long model   =BrokerOffsetFromUTC(TimeGMT());
   if(measured!=model)
     {
      PrintFormat("CNYClock [AVISO]: offset medido %+.1fh != modelo %+.1fh. "
                  "Revisa InpBrokerGMTWinter/InpBrokerDST o el reloj/zona horaria del VPS.",
                  measured/3600.0,model/3600.0);
      return false;
     }
   PrintFormat("CNYClock: offset broker %+.1fh coherente con el modelo. Hora NY actual: %s",
               model/3600.0,TimeToString(ServerToNY(TimeTradeServer()),TIME_DATE|TIME_MINUTES));
   return true;
  }

//+------------------------------------------------------------------+
//| Histórico (válido en tester): la apertura semanal FX es domingo  |
//| 17:00 NY. Con el modelo correcto, la hora NY de cada apertura    |
//| debe ser SIEMPRE la misma, también en las semanas de desajuste   |
//| DST EE.UU./Europa. Devuelve nº de semanas incoherentes (-1 = sin |
//| datos suficientes).                                              |
//+------------------------------------------------------------------+
int CNYClock::ValidateHistory(const int maxBars)
  {
   datetime t[];
   ResetLastError();
   int n=CopyTime(_Symbol,PERIOD_H1,0,maxBars,t);   // orden ascendente
   if(n<500)
     {
      PrintFormat("CNYClock: histórico H1 insuficiente para validar DST (n=%d, err=%d)",n,GetLastError());
      return -1;
     }
   int hist[24]; ArrayInitialize(hist,0);
   int opens=0;
   for(int i=1;i<n;i++)
     {
      if(t[i]-t[i-1]<36*3600) continue;            // solo huecos de fin de semana
      MqlDateTime s; TimeToStruct(ServerToNY(t[i]),s);
      if(s.day_of_week!=0) continue;                // aperturas en domingo NY
      hist[s.hour]++; opens++;
     }
   if(opens<4)
     {
      Print("CNYClock: pocas aperturas semanales para validar DST");
      return -1;
     }
   int dom=0;
   for(int h=1;h<24;h++) if(hist[h]>hist[dom]) dom=h;
   int mismatches=opens-hist[dom];
   //--- Con el modelo equivocado fallan TODAS las semanas de desajuste DST (~4 por año).
   //--- 1-2 aperturas atípicas sueltas = festivos o huecos de datos del broker.
   const bool bad=(dom<16 || dom>18 || mismatches>MathMax(2,opens/20));
   if(bad)
      PrintFormat("CNYClock [AVISO]: %d/%d aperturas semanales no cuadran (hora NY dominante %02d:00). "
                  "Configuración GMT/DST del broker probablemente INCORRECTA.",mismatches,opens,dom);
   else
      PrintFormat("CNYClock: %d/%d aperturas semanales coherentes a las %02d:00 NY (%d atípicas: festivos/huecos). Modelo DST OK.",
                  opens-mismatches,opens,dom,mismatches);
   if(!bad) return 0;
   return mismatches;
  }

#endif // SB_NYCLOCK_MQH
//+------------------------------------------------------------------+
