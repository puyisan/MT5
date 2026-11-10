//+------------------------------------------------------------------+
//|                                               SB_WindowsDraw.mqh |
//|  Franjas de las ventanas Silver Bullet en el gráfico (solo       |
//|  visual): margen previo en tono claro, ventana en tono medio,    |
//|  líneas de inicio/fin y etiqueta con nombre y horario NY.        |
//|  Las horas salen del mismo reloj NY que usa el EA (DST incluido).|
//|  Coste: se construye una vez por día NY; en cada vela nueva solo |
//|  se actualiza el rango de las ventanas de hoy; las etiquetas se  |
//|  recolocan al mover o escalar el gráfico.                        |
//+------------------------------------------------------------------+
#ifndef SB_WINDOWSDRAW_MQH
#define SB_WINDOWSDRAW_MQH

#include "SB_Defines.mqh"
#include "SB_NYClock.mqh"

#define SB_WD_PREFIX   "SB_W"          // empieza por SB_OBJ_PREFIX: OnDeinit los borra
#define SB_WD_MAXDAYS  20

struct SWinBand
  {
   string            key;        // prefijo de los objetos de esta ventana
   int               idx;        // 0 Londres, 1 AM, 2 PM
   datetime          lead;       // inicio del margen previo (hora servidor)
   datetime          start;      // inicio de la ventana
   datetime          end;        // fin de la ventana
   double            hi;         // máximo del precio en [lead, end)
   double            lo;         // mínimo del precio en [lead, end)
   bool              hasBars;
  };

class CWindowDrawer
  {
private:
   CNYClock         *m_clock;
   bool              m_on;
   int               m_days;
   int               m_leadSec;
   double            m_hName;    // alto de la línea del nombre (píxeles del gráfico)
   double            m_hHours;   // alto de la línea del horario
   double            m_pad;      // margen al borde del gráfico
   bool              m_winOn[SB_MAX_WIN];
   int               m_startMin[SB_MAX_WIN];
   int               m_endMin[SB_MAX_WIN];
   string            m_name[SB_MAX_WIN];
   color             m_base[SB_MAX_WIN];
   SWinBand          m_bands[];
   string            m_dayKeys[];

   static color      Blend(const color a,const color b,const double t);
   static double     LineHeight(const int pts,const int dpi);
   static string     HHMM(const int minutes) { return StringFormat("%02d:%02d",minutes/60,minutes%60); }
   void              MakeRect(const string n,const datetime t1,const datetime t2,const color c,const string tip);
   void              MakeVLine(const string n,const datetime t,const color c,const ENUM_LINE_STYLE st,const string tip);
   void              MakeText(const string n,const string txt,const color c,const int size,const string tip);
   void              PlaceText(const string n,const datetime t,const double price,const ENUM_ANCHOR_POINT anchor);
   void              UpdateRange(SWinBand &b);
   void              DeleteDay(const string dayKey) { ObjectsDeleteAll(0,SB_WD_PREFIX+dayKey); }

public:
                     CWindowDrawer(void) : m_clock(NULL),m_on(false),m_days(5),m_leadSec(0),m_hName(16),m_hHours(14),m_pad(3) {}
   void              Init(CNYClock *clock,const bool on,const int days,const int leadMin,
                          const bool winLondon,const bool winAM,const bool winPM,
                          const int &startMin[],const int &endMin[]);
   void              Rebuild(void);        // al iniciar y en cada nuevo día NY
   void              OnNewBar(void);       // rango de las ventanas de hoy + recolocar etiquetas
   void              Reposition(void);     // al mover / escalar el gráfico
  };

//+------------------------------------------------------------------+
void CWindowDrawer::Init(CNYClock *clock,const bool on,const int days,const int leadMin,
                         const bool winLondon,const bool winAM,const bool winPM,
                         const int &startMin[],const int &endMin[])
  {
   m_clock  =clock;
   m_on     =on && (clock!=NULL);
   m_days   =MathMax(1,MathMin(days,SB_WD_MAXDAYS));
   m_leadSec=MathMax(0,leadMin)*60;
   m_winOn[0]=winLondon; m_winOn[1]=winAM; m_winOn[2]=winPM;
   m_name[0]="LONDON";  m_name[1]="NEW YORK AM";   m_name[2]="NEW YORK PM";
   m_base[0]=C'70,130,220';    // azul
   m_base[1]=C'235,150,30';    // naranja
   m_base[2]=C'150,100,210';   // violeta
   for(int i=0;i<SB_MAX_WIN;i++) { m_startMin[i]=startMin[i]; m_endMin[i]=endMin[i]; }
   //--- alto de línea según los DPI de la pantalla (en un Mac Retina el texto mide el doble)
   int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<=0) dpi=96;
   m_hName =LineHeight(9,dpi);
   m_hHours=LineHeight(8,dpi);
   m_pad   =3.0*dpi/96.0;
   ArrayResize(m_bands,0);
   ArrayResize(m_dayKeys,0);
  }

//+------------------------------------------------------------------+
//| Alto de una línea de texto en píxeles: el mayor entre la medida  |
//| real de la fuente y la estimación por DPI, con margen amplio:    |
//| solo fija la distancia al borde del gráfico (las dos líneas se   |
//| apilan por anclaje y nunca se solapan).                          |
//+------------------------------------------------------------------+
double CWindowDrawer::LineHeight(const int pts,const int dpi)
  {
   double h=pts*dpi/72.0;
   uint w=0,th=0;
   if(TextSetFont("Arial",-pts*10) && TextGetSize("LONDON 03:00",w,th) && th>0)
      h=MathMax(h,(double)th);
   return MathCeil(h*2.0);
  }

//+------------------------------------------------------------------+
//| Mezcla de colores: t=0 -> a, t=1 -> b (color = 0x00BBGGRR)       |
//+------------------------------------------------------------------+
color CWindowDrawer::Blend(const color a,const color b,const double t)
  {
   const uint ua=(uint)a, ub=(uint)b;
   const int ar=(int)(ua&0xFF), ag=(int)((ua>>8)&0xFF), ab=(int)((ua>>16)&0xFF);
   const int br=(int)(ub&0xFF), bg=(int)((ub>>8)&0xFF), bb=(int)((ub>>16)&0xFF);
   const int r =(int)MathRound(ar+(br-ar)*t);
   const int g =(int)MathRound(ag+(bg-ag)*t);
   const int bl=(int)MathRound(ab+(bb-ab)*t);
   return (color)(uint)(r|(g<<8)|(bl<<16));
  }

//+------------------------------------------------------------------+
//| Primitivas: los objetos existentes no se recrean, para que las   |
//| franjas queden siempre por debajo de los FVG dibujados después.  |
//+------------------------------------------------------------------+
void CWindowDrawer::MakeRect(const string n,const datetime t1,const datetime t2,const color c,const string tip)
  {
   if(ObjectFind(0,n)>=0) return;
   const double top=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Point)*10.0;   // muy por encima: altura completa
   if(!ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,0.0,t2,top)) return;
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetString(0,n,OBJPROP_TOOLTIP,tip);
  }

void CWindowDrawer::MakeVLine(const string n,const datetime t,const color c,const ENUM_LINE_STYLE st,const string tip)
  {
   if(ObjectFind(0,n)>=0) return;
   //--- línea de tendencia vertical (no muestra etiqueta en el eje de tiempo como OBJ_VLINE)
   const double top=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Point)*10.0;
   if(!ObjectCreate(0,n,OBJ_TREND,0,t,0.0,t,top)) return;
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_STYLE,st);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,n,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetString(0,n,OBJPROP_TOOLTIP,tip);
  }

void CWindowDrawer::MakeText(const string n,const string txt,const color c,const int size,const string tip)
  {
   if(ObjectFind(0,n)>=0) return;
   if(!ObjectCreate(0,n,OBJ_TEXT,0,0,0.0)) return;
   ObjectSetString(0,n,OBJPROP_TEXT,txt);
   ObjectSetString(0,n,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetString(0,n,OBJPROP_TOOLTIP,tip);
  }

void CWindowDrawer::PlaceText(const string n,const datetime t,const double price,const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0,n)<0) return;
   if((ENUM_ANCHOR_POINT)ObjectGetInteger(0,n,OBJPROP_ANCHOR)!=anchor)
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,anchor);
   if((datetime)ObjectGetInteger(0,n,OBJPROP_TIME,0)!=t ||
      MathAbs(ObjectGetDouble(0,n,OBJPROP_PRICE,0)-price)>_Point*0.5)
      ObjectMove(0,n,0,t,price);
  }

//+------------------------------------------------------------------+
//| Máximo/mínimo del precio dentro de la franja (TF del gráfico)    |
//+------------------------------------------------------------------+
void CWindowDrawer::UpdateRange(SWinBand &b)
  {
   b.hasBars=false;
   if(b.lead>TimeCurrent()) return;
   double h[],l[];
   const datetime stop=b.end-1;
   const int nh=CopyHigh(_Symbol,_Period,b.lead,stop,h);
   const int nl=CopyLow(_Symbol,_Period,b.lead,stop,l);
   if(nh<=0 || nl<=0) return;
   b.hi=h[ArrayMaximum(h)];
   b.lo=l[ArrayMinimum(l)];
   b.hasBars=true;
  }

//+------------------------------------------------------------------+
//| Construye las franjas de los últimos m_days días hábiles NY      |
//| (incluido hoy, también sus ventanas aún por llegar)              |
//+------------------------------------------------------------------+
void CWindowDrawer::Rebuild(void)
  {
   if(!m_on) return;
   const color bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   const datetime nyNow=m_clock.ServerToNY(TimeCurrent());
   datetime day=(datetime)(nyNow-(nyNow%86400));

   //--- días hábiles NY, del más reciente hacia atrás
   string keys[];
   datetime days[];
   ArrayResize(keys,0); ArrayResize(days,0);
   for(int guard=0;guard<3*SB_WD_MAXDAYS && ArraySize(days)<m_days;guard++,day-=86400)
     {
      MqlDateTime s; TimeToStruct(day,s);
      if(s.day_of_week==0 || s.day_of_week==6) continue;
      const int k=ArraySize(days);
      ArrayResize(days,k+1); ArrayResize(keys,k+1);
      days[k]=day;
      keys[k]=StringFormat("%04d%02d%02d",s.year,s.mon,s.day);
     }

   //--- borrar los días que ya no entran
   for(int i=0;i<ArraySize(m_dayKeys);i++)
     {
      bool keep=false;
      for(int j=0;j<ArraySize(keys) && !keep;j++) keep=(keys[j]==m_dayKeys[i]);
      if(!keep) DeleteDay(m_dayKeys[i]);
     }
   ArrayCopy(m_dayKeys,keys);
   ArrayResize(m_dayKeys,ArraySize(keys));

   //--- crear las que falten (del día más antiguo al más reciente)
   ArrayResize(m_bands,0);
   for(int d=ArraySize(days)-1;d>=0;d--)
     {
      for(int i=0;i<SB_MAX_WIN;i++)
        {
         if(!m_winOn[i]) continue;
         const int k=ArraySize(m_bands);
         ArrayResize(m_bands,k+1);
         m_bands[k].key  =SB_WD_PREFIX+keys[d]+"_"+IntegerToString(i)+"_";
         m_bands[k].idx  =i;
         m_bands[k].start=m_clock.NYToServer(days[d]+m_startMin[i]*60);
         m_bands[k].end  =m_clock.NYToServer(days[d]+m_endMin[i]*60);
         m_bands[k].lead =m_bands[k].start-m_leadSec;
         m_bands[k].hi=0.0; m_bands[k].lo=0.0; m_bands[k].hasBars=false;
         const string key=m_bands[k].key;
         const datetime tLead=m_bands[k].lead, tStart=m_bands[k].start, tEnd=m_bands[k].end;

         const string hours=HHMM(m_startMin[i])+"-"+HHMM(m_endMin[i])+" NY";
         const string tip  =StringFormat("%s %s (servidor %s-%s)",m_name[i],hours,
                                         TimeToString(tStart,TIME_MINUTES),TimeToString(tEnd,TIME_MINUTES));
         const color  base =m_base[i];
         const color  dark =Blend(base,clrBlack,0.30);
         if(m_leadSec>0)
           {
            MakeRect (key+"lead",tLead,tStart,Blend(bg,base,0.07),
                      StringFormat("%s: margen previo de %d min (un barrido aquí ya cuenta)",m_name[i],m_leadSec/60));
            MakeVLine(key+"l0",tLead,base,STYLE_DOT,tip);
            MakeText (key+"tl",StringFormat("-%d min ",m_leadSec/60),dark,8,tip);
           }
         MakeRect (key+"band",tStart,tEnd,Blend(bg,base,0.17),tip);
         MakeVLine(key+"l1",tStart,base,STYLE_SOLID,tip);
         MakeVLine(key+"l2",tEnd,base,STYLE_SOLID,tip);
         MakeText (key+"tn"," "+m_name[i],dark,9,tip);
         MakeText (key+"th"," "+hours,dark,8,tip);
         UpdateRange(m_bands[k]);
        }
     }
   Reposition();
  }

//+------------------------------------------------------------------+
//| Nueva vela: actualizar el rango de las ventanas en curso         |
//+------------------------------------------------------------------+
void CWindowDrawer::OnNewBar(void)
  {
   if(!m_on) return;
   const datetime now=TimeCurrent();
   const int n=ArraySize(m_bands);
   for(int k=0;k<n;k++)
      if(m_bands[k].lead<=now && now<m_bands[k].end+PeriodSeconds(_Period))
         UpdateRange(m_bands[k]);
   Reposition();
  }

//+------------------------------------------------------------------+
//| Etiquetas arriba o abajo, en el lado con más espacio libre       |
//+------------------------------------------------------------------+
void CWindowDrawer::Reposition(void)
  {
   if(!m_on) return;
   const double pmax=ChartGetDouble(0,CHART_PRICE_MAX,0);
   const double pmin=ChartGetDouble(0,CHART_PRICE_MIN,0);
   const long   hpx =ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(pmax<=pmin || hpx<=0) return;
   const double pp=(pmax-pmin)/(double)hpx;     // precio por píxel
   const int n=ArraySize(m_bands);
   for(int k=0;k<n;k++)
     {
      const string   key  =m_bands[k].key;
      const datetime tStart=m_bands[k].start;
      bool top=true;
      if(m_bands[k].hasBars) top=((pmax-m_bands[k].hi)>=(m_bands[k].lo-pmin));
      //--- dos líneas a la derecha de la línea de inicio: el nombre se apoya ENCIMA de y
      //--- (ancla inferior) y el horario cuelga DEBAJO (ancla superior). Así nunca se solapan,
      //--- sea cual sea el tamaño real de la fuente (pantallas Retina). "-30 min" va en la fila
      //--- del horario, a la izquierda de la línea, dentro del margen previo.
      const double y=top?pmax-(m_pad+m_hName)*pp:pmin+(m_pad+m_hHours)*pp;
      PlaceText(key+"tn",tStart,y,ANCHOR_LEFT_LOWER);
      PlaceText(key+"th",tStart,y,ANCHOR_LEFT_UPPER);
      PlaceText(key+"tl",tStart,y,ANCHOR_RIGHT_UPPER);
     }
   ChartRedraw(0);
  }

#endif // SB_WINDOWSDRAW_MQH
//+------------------------------------------------------------------+
