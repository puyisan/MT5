//+------------------------------------------------------------------+
//|                                                   SB_Journal.mqh |
//|  Registro CSV de operaciones cerradas (una línea por posición).  |
//|  Incluye precio pedido vs ejecutado (deslizamiento real), SL/TP  |
//|  iniciales, tipo de salida, resultado en USD y en R.             |
//|  Solo se escribe al cerrar una posición: coste nulo en OnTick.   |
//+------------------------------------------------------------------+
#ifndef SB_JOURNAL_MQH
#define SB_JOURNAL_MQH

class CTradeJournal
  {
private:
   bool              m_on;
   string            m_file;
   int               m_flags;        // FILE_COMMON o 0
   ulong             m_magic;
   string            m_symbol;
   string            m_version;

   static string     Ts(const datetime t)
     {
      string s=TimeToString(t,TIME_DATE|TIME_SECONDS);   // 2026.11.09 17:05:00
      StringReplace(s,".","-");
      return s;
     }
   static string     WindowName(const string code)
     {
      if(code=="03-04NY") return "Londres";
      if(code=="10-11NY") return "AM";
      if(code=="14-15NY") return "PM";
      return code;
     }
   //--- "[sl 1.17801]" / "tp 1.16803" -> precio; 0 si no hay
   static double     PriceFromComment(const string comment)
     {
      string c=comment;
      StringToLower(c);
      int p=StringFind(c,"sl ");
      if(p<0) p=StringFind(c,"tp ");
      if(p<0) return 0.0;
      string num="";
      for(int i=p+3;i<StringLen(c);i++)
        {
         const ushort ch=StringGetCharacter(c,i);
         if((ch>='0' && ch<='9') || ch=='.') num+=ShortToString(ch);
         else if(StringLen(num)>0) break;
        }
      return (StringLen(num)>0)?StringToDouble(num):0.0;
     }
   bool              WriteLine(const string line);
   static string     Num1(const double x) { return DoubleToString((MathAbs(x)<0.05)?0.0:x,1); }   // sin "-0.0" 

public:
                     CTradeJournal(void) : m_on(false),m_file(""),m_flags(0),m_magic(0),m_symbol(""),m_version("") {}
   bool              Init(const bool on,const string file,const bool common,const bool truncate,
                          const ulong magic,const string symbol,const string version);
   bool              Enabled(void) const { return m_on; }
   string            FullPath(void) const;
   string            OnDeal(const ulong deal,const string eaCloseReason,const double eaClosePrice);   // resumen o "" 
  };

//+------------------------------------------------------------------+
bool CTradeJournal::Init(const bool on,const string file,const bool common,const bool truncate,
                         const ulong magic,const string symbol,const string version)
  {
   m_on=on; m_file=file; m_flags=common?FILE_COMMON:0;
   m_magic=magic; m_symbol=symbol; m_version=version;
   if(!m_on) return true;

   ResetLastError();
   const int mode=truncate?(FILE_WRITE|FILE_CSV|FILE_ANSI):(FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
   const int h=FileOpen(m_file,mode|m_flags,',');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("Registro: no se pudo abrir %s (err=%d). El registro queda desactivado.",m_file,GetLastError());
      m_on=false;
      return false;
     }
   if(FileSize(h)==0)
      FileWrite(h,"ticket","abierta","cerrada","dir","ventana","nivel","lotes",
                "entrada_pedida","entrada","sl_inicial","tp_inicial","salida_pedida","salida_precio","salida",
                "usd","r","slip_entrada_pts","slip_salida_pts","balance","version");
   FileClose(h);
   return true;
  }

string CTradeJournal::FullPath(void) const
  {
   const string base=(m_flags==FILE_COMMON)?TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"
                                            :TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5\\Files\\";
   return base+m_file;
  }

bool CTradeJournal::WriteLine(const string line)
  {
   ResetLastError();
   const int h=FileOpen(m_file,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|m_flags);
   if(h==INVALID_HANDLE)
     {
      PrintFormat("Registro: no se pudo escribir en %s (err=%d)",m_file,GetLastError());
      return false;
     }
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,line+"\r\n");
   FileClose(h);
   return true;
  }

//+------------------------------------------------------------------+
//| Llamar desde OnTradeTransaction con cada DEAL_ADD                |
//+------------------------------------------------------------------+
string CTradeJournal::OnDeal(const ulong deal,const string eaCloseReason,const double eaClosePrice)
  {
   //--- se procesa siempre (para la notificación); el archivo solo se escribe si m_on
   if(deal==0) return "";
   if(!HistoryDealSelect(deal)) return "";
   if(HistoryDealGetString(deal,DEAL_SYMBOL)!=m_symbol) return "";
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)m_magic) return "";
   const ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(de!=DEAL_ENTRY_OUT && de!=DEAL_ENTRY_OUT_BY && de!=DEAL_ENTRY_INOUT) return "";

   const ulong posId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(PositionSelectByTicket(posId)) return "";              // cierre parcial: esperar al cierre total
   if(!HistorySelectByPosition(posId)) return "";

   //--- recorrer los deals de la posición
   datetime tIn=0,tOut=0;
   double   pxIn=0,pxOut=0,vol=0,usd=0;
   ulong    ordIn=0,ordOut=0;
   string   cmtIn="",cmtOut="";
   long     typeIn=-1,reasonOut=-1;
   const int nd=HistoryDealsTotal();
   for(int i=0;i<nd;i++)
     {
      const ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      const ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e==DEAL_ENTRY_IN)
        {
         tIn=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         pxIn=HistoryDealGetDouble(d,DEAL_PRICE);
         vol=HistoryDealGetDouble(d,DEAL_VOLUME);
         ordIn=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
         cmtIn=HistoryDealGetString(d,DEAL_COMMENT);
         typeIn=HistoryDealGetInteger(d,DEAL_TYPE);
        }
      else
        {
         tOut=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         pxOut=HistoryDealGetDouble(d,DEAL_PRICE);
         ordOut=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
         cmtOut=HistoryDealGetString(d,DEAL_COMMENT);
         reasonOut=HistoryDealGetInteger(d,DEAL_REASON);
        }
      usd+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_COMMISSION)+
           HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_FEE);
     }
   if(tIn==0 || tOut==0) return "";

   const int    dir=(typeIn==DEAL_TYPE_BUY)?+1:-1;
   const double pt=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   const int    dg=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);

   //--- orden de apertura: precio pedido y SL/TP iniciales
   double reqIn=0,slIn=0,tpIn=0;
   if(ordIn>0 && HistoryOrderSelect(ordIn))
     {
      reqIn=HistoryOrderGetDouble(ordIn,ORDER_PRICE_OPEN);
      slIn =HistoryOrderGetDouble(ordIn,ORDER_SL);
      tpIn =HistoryOrderGetDouble(ordIn,ORDER_TP);
     }
   //--- precio pedido de salida: el nivel del SL/TP (comentario del servidor) o la orden de cierre
   double reqOut=PriceFromComment(cmtOut);
   if(reqOut<=0.0 && ordOut>0 && HistoryOrderSelect(ordOut))
      reqOut=HistoryOrderGetDouble(ordOut,ORDER_PRICE_OPEN);
   if(reqOut<=0.0 && (ENUM_DEAL_REASON)reasonOut==DEAL_REASON_EXPERT)
      reqOut=eaClosePrice;                                   // cierre por tiempo / viernes: precio al enviar

   //--- tipo de salida
   string exitType="otro";
   switch((ENUM_DEAL_REASON)reasonOut)
     {
      case DEAL_REASON_SL:     exitType=(usd>0.0)?"BE":"SL"; break;
      case DEAL_REASON_TP:     exitType="TP"; break;
      case DEAL_REASON_EXPERT: exitType=(eaCloseReason!="")?eaCloseReason:"EA"; break;
      case DEAL_REASON_SO:     exitType="stop out"; break;
      case DEAL_REASON_CLIENT:
      case DEAL_REASON_MOBILE:
      case DEAL_REASON_WEB:    exitType="manual"; break;
      default: break;
     }

   //--- R y deslizamiento (positivo = peor de lo pedido)
   const double risk=(reqIn>0 && slIn>0)?MathAbs(reqIn-slIn):0.0;
   const string rStr=(risk>0)?DoubleToString(dir*(pxOut-pxIn)/risk,2):"";
   const string slipIn =(reqIn>0 && pt>0)?Num1(dir*(pxIn-reqIn)/pt):"";
   const string slipOut=(reqOut>0 && pt>0)?Num1(dir*(reqOut-pxOut)/pt):"";

   //--- contexto desde el comentario "SB2 10-11NY EMA50"
   string parts[];
   string win="",lvl="";
   if(StringSplit(cmtIn,' ',parts)>=3 && (parts[0]=="SB" || parts[0]=="SB2" || parts[0]=="IM")) { win=WindowName(parts[1]); lvl=parts[2]; }

   const string line=StringFormat("%I64u,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                                  posId,Ts(tIn),Ts(tOut),(dir>0)?"compra":"venta",win,lvl,
                                  DoubleToString(vol,2),
                                  (reqIn>0)?DoubleToString(reqIn,dg):"",DoubleToString(pxIn,dg),
                                  (slIn>0)?DoubleToString(slIn,dg):"",(tpIn>0)?DoubleToString(tpIn,dg):"",
                                  (reqOut>0)?DoubleToString(reqOut,dg):"",DoubleToString(pxOut,dg),exitType,
                                  DoubleToString(usd,2),rStr,slipIn,slipOut,
                                  DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),m_version);
   if(m_on && WriteLine(line))
      PrintFormat("Registro: posición #%I64u anotada (%s, %s USD, %s R)",posId,exitType,DoubleToString(usd,2),rStr);
   return StringFormat("Cierre %s %s %s: %s %s USD%s",(dir>0)?"COMPRA":"VENTA",win,lvl,exitType,
                       DoubleToString(usd,2),(rStr!="")?" ("+rStr+" R)":"");
  }

#endif // SB_JOURNAL_MQH
//+------------------------------------------------------------------+
