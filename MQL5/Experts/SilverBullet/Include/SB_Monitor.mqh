//+------------------------------------------------------------------+
//|                                                   SB_Monitor.mqh |
//|  Supervisión en vivo:                                            |
//|   - CNotifier: notificaciones push a la app móvil de MT5         |
//|     (Herramientas → Opciones → Notificaciones, MetaQuotes ID).   |
//|   - CStatusFile: archivo de estado sobrescrito cada N minutos    |
//|     (latido) para que el panel sepa si el EA sigue vivo.         |
//|  Nada de esto corre en el Strategy Tester ni en optimización.    |
//+------------------------------------------------------------------+
#ifndef SB_MONITOR_MQH
#define SB_MONITOR_MQH

//+------------------------------------------------------------------+
class CNotifier
  {
private:
   bool              m_on;
   string            m_prefix;
   datetime          m_lastSent;
   int               m_sentThisMin;

public:
                     CNotifier(void) : m_on(false),m_prefix(""),m_lastSent(0),m_sentThisMin(0) {}
   void              Init(const bool on,const string prefix)
     {
      const bool tester=(bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
      m_on=on && !tester;
      m_prefix=prefix;
      if(m_on && !TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
         Print("Notificaciones: desactivadas en el terminal. Actívalas en Herramientas → Opciones → Notificaciones "
               "e introduce el MetaQuotes ID de la app móvil de MT5.");
     }
   //--- límite del servidor: 2 por segundo y 10 por minuto
   bool              Send(const string text)
     {
      if(!m_on) return false;
      const datetime now=TimeLocal();
      if(now/60!=m_lastSent/60) m_sentThisMin=0;
      if(m_sentThisMin>=8) { PrintFormat("Notificación omitida (límite por minuto): %s",text); return false; }
      string msg=m_prefix+text;
      if(StringLen(msg)>255) msg=StringSubstr(msg,0,252)+"...";
      ResetLastError();
      if(!SendNotification(msg))
        {
         PrintFormat("Notificación no enviada (err=%d): %s",GetLastError(),msg);
         return false;
        }
      m_lastSent=now; m_sentThisMin++;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| Fila única de estado, sobrescrita en cada latido                 |
//+------------------------------------------------------------------+
struct SStatusRow
  {
   string            version;
   string            estado;
   string            ventana;
   double            equity;
   double            balance;
   double            pico;
   double            dd_pct;
   bool              freno;
   int               posiciones;
   int               pendientes;
   bool              conectado;
   bool              trading;
   int               errores;
   string            ultimo_error;
  };

class CStatusFile
  {
private:
   bool              m_on;
   string            m_file;
   int               m_flags;

   static string     Clean(const string s)
     {
      string t=s;
      StringReplace(t,",",";");
      StringReplace(t,"\r"," ");
      StringReplace(t,"\n"," ");
      return t;
     }
   static string     Ts(const datetime t)
     {
      string s=TimeToString(t,TIME_DATE|TIME_SECONDS);
      StringReplace(s,".","-");
      return s;
     }

public:
                     CStatusFile(void) : m_on(false),m_file(""),m_flags(0) {}
   void              Init(const bool on,const string file,const bool common)
     {
      const bool tester=(bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
      m_on=on && !tester; m_file=file; m_flags=common?FILE_COMMON:0;
     }
   bool              Enabled(void) const { return m_on; }
   bool              Write(const SStatusRow &s)
     {
      if(!m_on) return false;
      ResetLastError();
      const int h=FileOpen(m_file,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|m_flags);
      if(h==INVALID_HANDLE)
        {
         PrintFormat("Estado: no se pudo escribir %s (err=%d)",m_file,GetLastError());
         return false;
        }
      //--- hora UTC en ISO para que el panel calcule la antigüedad del latido
      string utc=TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS);
      StringReplace(utc,".","-");
      StringReplace(utc," ","T");
      FileWriteString(h,"actualizado_servidor,actualizado_utc,version,estado,ventana,equity,balance,pico_equity,dd_pct,"
                        "freno,posiciones,pendientes,conectado,trading_permitido,errores,ultimo_error\r\n");
      FileWriteString(h,StringFormat("%s,%sZ,%s,%s,%s,%.2f,%.2f,%.2f,%.4f,%d,%d,%d,%d,%d,%d,%s\r\n",
                                     Ts(TimeTradeServer()),utc,s.version,s.estado,s.ventana,
                                     s.equity,s.balance,s.pico,s.dd_pct,(int)s.freno,s.posiciones,s.pendientes,
                                     (int)s.conectado,(int)s.trading,s.errores,Clean(s.ultimo_error)));
      FileClose(h);
      return true;
     }
  };

#endif // SB_MONITOR_MQH
//+------------------------------------------------------------------+
