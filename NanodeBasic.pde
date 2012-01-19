// NanodeBasic.pde : An implementation of TinyBASIC in C to run on Nanode
//
// This version is Nanode specific as it requires the extra SRAM and optional uSD socket to work
//
// Take on the Nanode Tiny Basic Christmas Challenge
//
// Help Hack Tiny Basic onto Nanode and kickstart a return to simpler and fun programming
// Tiny Basic can help teach kids to program
//
// see  http://sustburbia.blogspot.com/2011_12_01_archive.html
//
// HAPPY CHRISTMAS 2011 Everyone!
//
// Join us on the #Nanode IRC Channel  http://webchat.freenode.net/?channels=nanode
//
// Arduino Tiny Basic Author : Mike Field - hamster@snap.net.nz
// Thanks to Dave CJ   (@ceejay on Twitter) for the digital, analogue and sleep functions
//
// SRAM implementation and new commands added by Andrew Lindsay @andrewdlindsay
// New commands:
//    DIR             - List files in root directory of uSD card
//    LOAD file.bas   - Load a program from uSD card filenames are 8.3 format only.
//    SAVE file.bas   - Save program to uSD card
//    LRUN file.bas   - Load and run program from uSD card
//    MEM             - Display basic memory usage values
//    TSECS           - function to return 1/10 sec (millis()/100) as int, so only low 15 bits.
//    SERVO           - Control a servo on pin 3, 5 or 6
//
//  If a file is found on the uSD card called autoexec.bas then it is loaded and run on powerup and reset.
//  Use CTRL-C to break out of running program.
//
// Based on TinyBasic for 68000, by Gordon Brandly
// (see http://members.shaw.ca/gbrandly/68ktinyb.html)
//
// which itself was Derived from Palo Alto Tiny BASIC as 
// published in the May 1976 issue of Dr. Dobb's Journal.  
// 
// 0.03 21/01/2011 : Added INPUT routine 
//                 : Reorganised memory layout
//                 : Expanded all error messages
//                 : Break key added
//                 : Removed the calls to printf (left by debugging)

// comment out to not include SdFat code.
#define USESD

// Define the Select pins for the various devices
#define RFM12B_CS_PIN 10
#define SRAM_CS_PIN    9
#define ENC_CS_PIN     8
#define SDCARD_CS_PIN  4

#ifdef USESD
#include <SdFat.h>
#endif
#include <SRAM9.h>
#include <EEPROM.h>
// On Nanode we can only use servos on pins 3, 5 and 6
// Needs testing for multiple servos at once.
#include <Servo.h>

// Define size of SRAM buffer by setting start and end values. Default is all ram.
#define SRAM_START 0
#define SRAM_END 32767

// ASCII Characters
#define CR	'\r'
#define NL	'\n'
#define TAB	'\t'
#define BELL	'\b'
#define DEL	'\177'
#define SPACE   ' '
#define CTRLC	0x03
#define CTRLH	0x08
#define CTRLS	0x13
#define CTRLX	0x18

typedef short unsigned LINENUM;

/***********************************************************/
// Keyword table and constants - the last character has 0x80 added to it
static unsigned char keywords[] = {
  'L','I','S','T'+0x80,
  'L','O','A','D'+0x80,
  'N','E','W'+0x80,
  'R','U','N'+0x80,
  'S','A','V','E'+0x80,
  'N','E','X','T'+0x80,
  'L','E','T'+0x80,
  'I','F'+0x80,
  'G','O','T','O'+0x80,
  'G','O','S','U','B'+0x80,
  'R','E','T','U','R','N'+0x80,
  'R','E','M'+0x80,
  'F','O','R'+0x80,
  'I','N','P','U','T'+0x80,
  'P','R','I','N','T'+0x80,
  'P','O','K','E'+0x80,
  'S','T','O','P'+0x80,
  'B','Y','E'+0x80,
  'D','O','U','T'+0x80,
  'A','O','U','T'+0x80,
  'S','L','E','E','P'+0x80,
  'M','E','M'+0x80,
  'D','I','R'+0x80,
  'L','R','U','N'+0x80,
  'E','P','O','K','E'+0x80,
  'S','E','R','V','O'+0x80,
  0
};

#define KW_LIST		0
#define KW_LOAD		1
#define KW_NEW		2
#define KW_RUN		3
#define KW_SAVE		4
#define KW_NEXT		5
#define KW_LET		6
#define KW_IF		7
#define KW_GOTO		8
#define KW_GOSUB	9
#define KW_RETURN	10
#define KW_REM		11
#define KW_FOR		12
#define KW_INPUT	13
#define KW_PRINT	14
#define KW_POKE		15
#define KW_STOP		16
#define KW_BYE		17
#define KW_DOUT	        18
#define KW_AOUT	        19
#define KW_SLEEP	20
#define KW_MEM  	21
#define KW_DIR  	22
#define KW_LRUN		23
#define KW_EPOKE	24
#define KW_SERVO	25
#define KW_DEFAULT	26

struct stack_for_frame {
  char frame_type;
  char for_var;
  short int terminal;
  short int step;
  unsigned int current_line;
  unsigned int txtpos;
};

struct stack_gosub_frame {
  char frame_type;
  unsigned int current_line;
  unsigned int txtpos;
};

static unsigned char func_tab[] = {
  'P','E','E','K'+0x80,
  'A','B','S'+0x80,
  'D','I','N'+0x80,
  'A','I','N'+0x80,
  'H','I','G','H'+0x80,
  'L','O','W'+0x80,
  'T','S','E','C','S'+0x80,
  'E','P','E','E','K'+0x80,
  'R','N','D'+0x80,
  0
};

#define FUNC_PEEK 0
#define FUNC_ABS  1
#define FUNC_DIN  2
#define FUNC_AIN  3
#define FUNC_HIGH 4
#define FUNC_LOW  5
#define FUNC_TSECS  6
#define FUNC_EPEEK 7
#define FUNC_RND 8
#define FUNC_UNKNOWN 9

static unsigned char to_tab[] = {
  'T','O'+0x80,
  0
};

static unsigned char step_tab[] = {
  'S','T','E','P'+0x80,
  0
};

static unsigned char relop_tab[] = {
  '>','='+0x80,
  '<','>'+0x80,
  '>'+0x80,
  '='+0x80,
  '<','='+0x80,
  '<'+0x80,
  0
};

#define RELOP_GE  0
#define RELOP_NE  1
#define RELOP_GT  2
#define RELOP_EQ  3
#define RELOP_LE  4
#define RELOP_LT  5
#define RELOP_UNKNOWN  6

// Size of variables in bytes
#define VAR_SIZE sizeof(unsigned int)

static unsigned char expression_error;
static unsigned int txtpos,list_line;
static unsigned int tempsp;
static unsigned int stack_limit;
static unsigned int program_start;
static unsigned int program_end;
static unsigned int variables_table;
static unsigned int current_line;
static unsigned int sp;

#define STACK_GOSUB_FLAG 'G'
#define STACK_FOR_FLAG 'F'
static unsigned char table_index;
static LINENUM linenum;
static boolean sdcardFitted = false;

// For some reason if this is in flash it doesn't work!
static const unsigned char backspacemsg[] = "\b \b";

prog_char sramfail[] PROGMEM       = "SRAM failure";
prog_char freemem[] PROGMEM        = "Free Mem: ";
prog_char okmsg[] PROGMEM	   = "OK";
prog_char badlinemsg[]	PROGMEM	   = "Invalid line number";
prog_char invalidexprmsg[] PROGMEM = "Invalid expression";
prog_char syntaxmsg[] PROGMEM      = "Syntax Error";
prog_char badinputmsg[] PROGMEM    = "\nBad number";
prog_char nomemmsg[] PROGMEM       = "Not enough memory!";
prog_char initmsg[] PROGMEM        = "NanodeBasic V0.5";
prog_char memorymsg[] PROGMEM      = " bytes";
prog_char breakmsg[] PROGMEM       = "break!";
prog_char stackstuffedmsg[] PROGMEM = "Stack is stuffed!\n";
prog_char badportmsg[] PROGMEM        = "Invalid I/O port";
//prog_char unimplimentedmsg[] PROGMEM = "Unimplemented";
#ifdef USESD
prog_char sdinitfailmsg[] PROGMEM  = "uSD not found";
prog_char sdfileerrormsg[] PROGMEM = "Error opening file";
prog_char sdfilesaving[] PROGMEM   = "Saving..";
prog_char autoexecmsg[] PROGMEM    = "Autorunning autoexec.bas";
#endif

static int inchar(void);
static void outchar(unsigned char c);
static void line_terminator(void);
static short int expression(void);
static unsigned char breakcheck(void);
static char filename[13] = "autoexec.bas";

// Record state of digital and analog pin states
// INPUT and OUTPUT are already defined as 1 and 0, use UNDEFINED for initial state
// Use UNUSED to block use of port, e.g. 4 as this stops use of SD card and 9-13
#define UNDEFINED -1
#define UNUSED     2 
static byte digitalPinMode[14] = {UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED, UNUSED,
      UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED, UNUSED, UNUSED, UNUSED,
      UNUSED, UNUSED };

static byte analogPinMode[6] = {UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED, UNDEFINED };

// Servo object
Servo servo;

#ifdef USESD
SdFat sd;
SdFile sdCard;
SdVolume volume;
SdFile root;
#endif

static int freeRam () {
  extern int __heap_start, *__brkval; 
  int v; 
  return (int) &v - (__brkval == 0 ? (int) &__heap_start : (int) __brkval); 
}

/***************************************************************************/
static void ignore_blanks(void)
{
  while(readMemory(txtpos) == SPACE || readMemory(txtpos) == TAB)
    txtpos++;
}

/***************************************************************************/
static void scantable(unsigned char *table)
{
  int i = 0;
  ignore_blanks();
  table_index = 0;
  while(1)
  {
    // Run out of table entries?
    if(table[0] == 0)
      return;

    // Do we match this character?
    if(readMemory(txtpos+i) == table[0])
    {
      i++;
      table++;
    }
    else
    {
      // do we match the last character of keywork (with 0x80 added)? If so, return
      if(readMemory(txtpos+i)+0x80 == table[0])
      {
        txtpos += (i+1);  // Advance the pointer to following the keyword
        ignore_blanks();
        return;
      }

      // Forward to the end of this keyword
      while((table[0] & 0x80) == 0)
        table++;

      // Now move on to the first character of the next word, and reset the position index
      table++;
      table_index++;
      i = 0;
    }
  }
}

/***************************************************************************/
static void pushb(unsigned char b)
{
  sp--;
  writeMemory(sp, b);
}

/***************************************************************************/
static unsigned char popb()
{
  unsigned char b;
  b = readMemory(sp);
  sp++;
  return b;
}

/***************************************************************************/
static void printnum(int num)
{
  int digits = 0;

  if(num < 0)
  {
    num = -num;
    outchar('-');
  }

  do {
    pushb(num%10+'0');
    num = num/10;
    digits++;
  }
  while (num > 0);

  while(digits > 0)
  {
    outchar(popb());
    digits--;
  }
}
/***************************************************************************/
static unsigned short testnum(void)
{
  unsigned short num = 0;
  ignore_blanks();

  while(isDigitChar(txtpos) )
  {
    // Trap overflows
    if(num >= 0xFFFF/10)
    {
      num = 0xFFFF;
      break;
    }

    num = num *10 + (readMemory(txtpos) - '0');
    txtpos++;
  }
  return	num;
}

/***************************************************************************/
unsigned char check_statement_end(void)
{
  ignore_blanks();
  return (isNLChar(txtpos) || (readMemory(txtpos) == ':'));
}

/***************************************************************************/
static void printmsgNoNL(const unsigned char *msg)
{
  while(*msg)
  {
    outchar(*msg);
    msg++;
  }
}

static void printmsgNoNLP(const prog_char *msg)
{
  char ch;
  while( (ch = (char)pgm_read_byte(msg++)) != 0 ) {
    outchar( ch );
  }

}

/***************************************************************************/
static unsigned char print_quoted_string(void)
{
  int i=0;
  unsigned char delim = readMemory(txtpos);
  if(delim != '"' && delim != '\'')
    return 0;
  txtpos++;

  // Check we have a closing delimiter
  while(readMemory(txtpos+i) != delim)
  {
    if(isNLChar(txtpos+i))
      return 0;
    i++;
  }

  // Print the characters
  while(readMemory(txtpos) != delim)
  {
    outchar(readMemory(txtpos));
    txtpos++;
  }
  txtpos++; // Skip over the last delimiter
  ignore_blanks();

  return 1;
}

/***************************************************************************/
/*
static void printmsg(const unsigned char *msg)
{
  printmsgNoNL(msg);
  line_terminator();
}
*/

static void printmsgP( prog_char *msg)
//static void printmsgP( const unsigned char *msg)
{
  printmsgNoNLP(msg);
//  printmsgNoNL(msg);
  line_terminator();
}

/***************************************************************************/
unsigned char getln(char prompt)
{
  outchar(prompt);
  txtpos = program_end+sizeof(LINENUM);

  while(1)
  {
    char c = inchar();
    switch(c)
    {
    case CR:
    case NL:
      line_terminator();
      // Terminate all strings with a NL
      writeMemory(txtpos, NL);
      return 1;
    case CTRLC:
      return 0;
    case CTRLH:
//      if(txtpos == program_end) {
      if(txtpos <= (program_end+2)) {
//        Serial.println(F("BACK prog end reached"));
        break;
      }
      txtpos--;
      printmsgNoNL(backspacemsg);
      break;
    default:
      // We need to leave at least one space to allow us to shuffle the line into order
      if(txtpos == sp-2)
        outchar(BELL);
      else
      {
        writeMemory(txtpos, c);
        txtpos++;
        outchar(c);
      }
    }
  }
}


/***************************************************************************/
static unsigned int findline(void)
{
  unsigned int line = program_start;
  while(1)
  {
    if(line == program_end)
      return line;

    if(readMemoryInt(line) >= linenum)
      return line;

    // Add the line length onto the current address, to get to the next line;
    line += readMemory(line+sizeof(LINENUM));
  }
}

/***************************************************************************/
static void toUppercaseBuffer(void)
{
  int c = program_end+sizeof(LINENUM);
  unsigned char quote = 0;

  while(!isNLChar(c))
  {
    // Are we in a quoted string?
    unsigned char ch = readMemory(c);
    if(ch == quote)
      quote = 0;
    else if(ch == '"' || ch == '\'')
      quote = ch;
    else if(quote == 0 && isLowerChar(c))
      writeMemory(c, ( readMemory(c) + 'A' - 'a' ) );
    c++;
  }
}

/***************************************************************************/
void printline()
{
  LINENUM line_num;

  line_num = readMemoryInt(list_line);
  list_line += sizeof(LINENUM) + sizeof(char);

  // Output the line 
  printnum(line_num);
  outchar(' ');
  while(!isNLChar(list_line))
  {
    outchar(readMemory(list_line));
    list_line++;
  }
  list_line++;
  line_terminator();
}

#ifdef USESD
// Output a line to SD card, similar to LIST command
void printlineSD()
{
  LINENUM line_num;

  line_num = readMemoryInt(list_line);
  list_line += sizeof(LINENUM) + sizeof(char);

  // Output the line 
  sdCard.print(line_num);
  sdCard.print(' ');
  while(!isNLChar(list_line)) {
    sdCard.write(readMemory(list_line));
    list_line++;
  }
  list_line++;
  sdCard.print(NL);
  sdCard.print(CR);
}
#endif

/***************************************************************************/
static short int expr4(void)
{
  short int a = 0;

  if(readMemory(txtpos) == '0')
  {
    txtpos++;
    a = 0;
    goto success;
  }

  if(isDigitChar(txtpos))
  {
    do 	{
      a = a*10 + readMemory(txtpos) - '0';
      txtpos++;
    } 
    while(isDigitChar(txtpos));
    goto success;
  }

  // Is it a function or variable reference?
  if(isAlphaChar(txtpos))
  {
    // Is it a variable reference (single alpha)
    if(!isAlphaChar(txtpos+1))
    {
      a = readMemoryInt(variables_table + ((readMemory(txtpos) - 'A') * VAR_SIZE));
      txtpos++;
      goto success;
    }

    // Is it a function with a single parameter
    scantable(func_tab);
    if(table_index == FUNC_UNKNOWN)
      goto expr4_error;

    unsigned char f = table_index;

    if (f == FUNC_HIGH) {
      a=1;
      goto success;
    }
    if (f == FUNC_LOW) {
      a=0;
      goto success;
    }
    
    if( f == FUNC_TSECS ) {
      a = (int)( millis() / 100);
      goto success;
    }
    
    if(readMemory(txtpos) != '(')
      goto expr4_error;

    txtpos++;
    a = expression();
    if(readMemory(txtpos) != ')')
      goto expr4_error;
    txtpos++;
    switch(f)
    {
    case FUNC_PEEK:
      if( a >= SRAM_START && a <=SRAM_END ) {
        a = readMemory(a);
        goto success;
      }
      goto expr4_error;
    case FUNC_EPEEK:
      if( a >= 0 && a < 1024 ) {
        a = EEPROM.read(a);
        goto success;
      }
      goto expr4_error;
    case FUNC_ABS:
      if(a < 0)
        a = -a;
      goto success;
    case FUNC_DIN:
      if( a >= 0 && a <= 13 ) {
        if( checkAndSetDigitalPin( a, INPUT ) ) {
//          pinMode(a, INPUT);
          a = digitalRead(a);
          goto success;
        }
      }
      goto expr4_error;
    case FUNC_AIN:
      if( a >= 0 && a <= 5 ) {
//        if( checkAndSetAnalogPin( a, INPUT ) ) {
//          pinMode(a, INPUT);
          a = analogRead(a);
          goto success;
//        }
      }
      goto expr4_error;
    case FUNC_RND:
      if( a<=0 )
        goto expr4_error;
      
      a = (short int)random(a);
      goto success;
    }
  }

  if(readMemory(txtpos) == '(')
  {
    txtpos++;
    a = expression();
    if(readMemory(txtpos) != ')')
      goto expr4_error;

    txtpos++;
    goto success;
  }

expr4_error:
  expression_error = 1;
success:
  ignore_blanks();
  return a;
}

/***************************************************************************/
static short int expr3(void)
{
  short int a,b;
  unsigned char ch;

  a = expr4();
  while(1)
  {
    ch = readMemory(txtpos);
    if(ch == '*')
    {
      txtpos++;
      b = expr4();
      a *= b;
    }
    else if(ch == '/')
    {
      txtpos++;
      b = expr4();
      if(b != 0)
        a /= b;
      else
        expression_error = 1;
    }
    else
      return a;
  }
}

/***************************************************************************/
static short int expr2(void)
{
  short int a,b;
  unsigned char ch = readMemory(txtpos);

  if(ch == '-' || ch == '+')
    a = 0;
  else
    a = expr3();

  while(1)
  {
    ch = readMemory(txtpos);
    if(ch == '-')
    {
      txtpos++;
      b = expr3();
      a -= b;
    }
    else if(ch == '+')
    {
      txtpos++;
      b = expr3();
      a += b;
    }
    else
      return a;
  }
}
/***************************************************************************/
static short int expression(void)
{
  short int a,b;

  a = expr2();
  // Check if we have an error
  if(expression_error)	return a;

  scantable(relop_tab);
  if(table_index == RELOP_UNKNOWN)
    return a;

  switch(table_index)
  {
  case RELOP_GE:
    b = expr2();
    if(a >= b) return 1;
    break;
  case RELOP_NE:
    b = expr2();
    if(a != b) return 1;
    break;
  case RELOP_GT:
    b = expr2();
    if(a > b) return 1;
    break;
  case RELOP_EQ:
    b = expr2();
    if(a == b) return 1;
    break;
  case RELOP_LE:
    b = expr2();
    if(a <= b) return 1;
    break;
  case RELOP_LT:
    b = expr2();
    if(a < b) return 1;
    break;
  }
  return 0;
}

/***************************************************************************/
void loop()
{
  int n=0;
  boolean autoStart = false;
  
  //variables_table = memory;
  variables_table = SRAM_START;
  program_start = SRAM_START + 27*VAR_SIZE;
  program_end = program_start;
  sp = SRAM_START + (SRAM_END - SRAM_START);  // Needed for printnum
  printmsgP(initmsg);
  printnum(sp-program_end);
  printmsgP(memorymsg);

#ifdef USESD
  if( !sdcardFitted )
    printmsgP(sdinitfailmsg);
  else {
    // Check for a file called autoexec.bas, if it exists load and run
    if(sdCard.open(filename, O_READ )) {
      // close the file:
      sdCard.close();
      autoStart = true;
      printmsgP(autoexecmsg);
    }        
  }

#endif


warmstart:
  // this signifies that it is running in 'direct' mode.
  current_line = 0;
  sp = SRAM_START + (SRAM_END - SRAM_START);
  printmsgP(okmsg);

  if( autoStart ) {
    table_index = KW_LRUN;
    autoStart = false;
    goto load2;
  }

prompt:
  while(!getln('>'))
    line_terminator();
  toUppercaseBuffer();

  txtpos = program_end+sizeof(unsigned short);

  switch( addNewLine() ) {
  case 1:
    goto direct;
  case 2:
    goto badline;
  case 0:
  case 3:
    break;    // drops out to goto prompt
  }
  goto prompt;

//unimplemented:
//  printmsgP(unimplimentedmsg);
//  goto prompt;

badline:	
  printmsgP(badlinemsg);
  goto prompt;
invalidexpr:
  printmsgP(invalidexprmsg);
  goto prompt;
badporterror:
  printmsgP(badportmsg);
  goto syntaxerror2;
syntaxerror:
  printmsgP(syntaxmsg);
syntaxerror2:
  if(current_line != 0 )
  {
    unsigned int tmp = txtpos;
    if(!isNLChar(txtpos) != NL)
      writeMemory(txtpos, '^');
    list_line = current_line;
    printline();
    writeMemory(txtpos, tmp);
  }
  line_terminator();
  goto prompt;

stackstuffed:	
  printmsgP(stackstuffedmsg);
  goto warmstart;
nomem:	
  printmsgP(nomemmsg);
  goto warmstart;

run_next_statement:
  while(readMemory(txtpos) == ':')
    txtpos++;
  ignore_blanks();
  if(readMemory(txtpos) == NL)
    goto execnextline;
  goto interperateAtTxtpos;

direct: 
  txtpos = program_end+sizeof(LINENUM);
  if(readMemory(txtpos) == NL)
    goto prompt;

interperateAtTxtpos:
  if(breakcheck())
  {
    printmsgP(breakmsg);
    goto warmstart;
  }

  scantable(keywords);
  ignore_blanks();

  switch(table_index)
  {
  case KW_LIST:
    goto list;
#ifdef USESD
  case KW_LOAD:
    goto load;
#endif
  case KW_NEW:
    if(readMemory(txtpos) != NL)
      goto syntaxerror;
    program_end = program_start;
    goto prompt;
  case KW_RUN:
    current_line = program_start;
    goto execline;
#ifdef USESD
  case KW_SAVE:
    goto save;
#endif
  case KW_NEXT:
    goto next;
  case KW_LET:
    goto assignment;
  case KW_IF:
    {
      short int val;
      expression_error = 0;
      val = expression();
      if(expression_error || isNLChar(txtpos))
        goto invalidexpr;
      if(val != 0)
        goto interperateAtTxtpos;
      goto execnextline;
    }
  case KW_GOTO:
    expression_error = 0;
    linenum = expression();
    if(expression_error || !isNLChar(txtpos))
      goto invalidexpr;
    current_line = findline();
    goto execline;

  case KW_GOSUB:
    goto gosub;
  case KW_RETURN:
    goto gosub_return; 
  case KW_REM:	
    goto execnextline;	// Ignore line completely
  case KW_FOR:
    goto forloop; 
  case KW_INPUT:
    goto input; 
  case KW_PRINT:
    goto print;
  case KW_POKE:
  case KW_EPOKE:
    goto poke;
  case KW_STOP:
    // This is the easy way to end - set the current line to the end of program attempt to run it
    //			if(txtpos[0] != NL)
    if(!isNLChar(txtpos))
      goto syntaxerror;
    current_line = program_end;
    goto execline;
  case KW_BYE:
    // Leave the basic interperater
    return;
  case KW_DOUT:
    goto dout;
  case KW_AOUT:
    goto aout;
  case KW_SLEEP:
    goto sleep;
  case KW_MEM:
    goto displaymem;
#ifdef USESD
  case KW_DIR:
    goto dirsdcard;
  case KW_LRUN:
    goto load;
  case KW_SERVO:
    goto servo;  
#endif
  case KW_DEFAULT:
    goto assignment;
  default:
    break;
  }

execnextline:
  if(current_line == 0)		// Processing direct commands?
    goto prompt;
  current_line += readMemory(current_line + sizeof(LINENUM));

execline:
  if(current_line == program_end) // Out of lines to run
    goto warmstart;
  txtpos = current_line+sizeof(LINENUM)+sizeof(char);
  goto interperateAtTxtpos;

input:
  {
    unsigned char isneg=0;
    int temptxtpos;
    unsigned int var;
    ignore_blanks();
    if(!isAlphaChar(txtpos) )
      goto syntaxerror;
    var = variables_table + ((readMemory(txtpos)-'A') * VAR_SIZE );
    txtpos++;
    if(!check_statement_end())
      goto syntaxerror;
again:
    temptxtpos = txtpos;
    if(!getln('?'))
      goto warmstart;

    // Go to where the buffer is read
    txtpos = program_end+sizeof(LINENUM);
    if(readMemory(txtpos) == '-')
    {
      isneg = 1;
      txtpos++;
    }

    var = 0;
    do 	{
      var = var*10 + (readMemory(txtpos) - '0');
      txtpos++;
    } 
    while(isDigitChar(txtpos));
    ignore_blanks();
    if(!isNLChar(txtpos))
    {
      printmsgP(badinputmsg);
      goto again;
    }

    if(isneg)
      var *= -1;

    goto run_next_statement;
  }
forloop:
  {
    unsigned char var;
    short int initial, step, terminal;

    if(!isAlphaChar(txtpos))
      goto syntaxerror;
    var = readMemory(txtpos);
    txtpos++;

    scantable(relop_tab);
    if(table_index != RELOP_EQ)
      goto syntaxerror;

    expression_error = 0;
    initial = expression();
    if(expression_error)
      goto invalidexpr;

    scantable(to_tab);
    if(table_index != 0)
      goto syntaxerror;

    terminal = expression();
    if(expression_error)
      goto invalidexpr;

    scantable(step_tab);
    if(table_index == 0)
    {
      step = expression();
      if(expression_error)
        goto invalidexpr;
    }
    else
      step = 1;
      
    if(!check_statement_end())
      goto syntaxerror;

    if(!expression_error && isNLChar(txtpos) )
    {
      struct stack_for_frame f;
      if(sp + sizeof(struct stack_for_frame) < stack_limit)
        goto nomem;

      sp -= sizeof(struct stack_for_frame);
      writeMemoryInt(variables_table+ (var-'A')* VAR_SIZE, initial);

      f.frame_type = STACK_FOR_FLAG;
      f.for_var = var;
      f.terminal = terminal;
      f.step     = step;
      f.txtpos   = txtpos;
      f.current_line = current_line;
      writeStackFrame(sp, sizeof( struct stack_for_frame), (unsigned char*)&f);
      goto run_next_statement;
    }
  }
  goto syntaxerror;

gosub:
  expression_error = 0;
  linenum = expression();
  if(expression_error)
    goto invalidexpr;
  if(!expression_error && isNLChar(txtpos) )
  {
    struct stack_gosub_frame f;

    if(sp + sizeof(struct stack_gosub_frame) < stack_limit)
      goto nomem;

    sp -= sizeof(struct stack_gosub_frame);
    f.frame_type = STACK_GOSUB_FLAG;
    f.txtpos = txtpos;
    f.current_line = current_line;
    writeStackFrame(sp, sizeof( struct stack_gosub_frame), (unsigned char*)&f);

    current_line = findline();
    goto execline;
  }
  goto syntaxerror;

next:
  // Find the variable name
  ignore_blanks();
  if(!isAlphaChar(txtpos))
    goto syntaxerror;
  txtpos++;
  if(!check_statement_end())
    goto syntaxerror;

gosub_return:
  // Now walk up the stack frames and find the frame we want, if present
  tempsp = sp;
  while(tempsp < SRAM_END)
  {
    switch(readMemory(tempsp) )
    {
    case STACK_GOSUB_FLAG:
      if(table_index == KW_RETURN)
      {
        struct stack_gosub_frame f;
        //struct stack_gosub_frame *fptr = &f;
        getStackFrame(tempsp, sizeof( struct stack_gosub_frame), (unsigned char*)&f);
        current_line	= f.current_line;
        txtpos		= f.txtpos;
        sp += sizeof(struct stack_gosub_frame);
        goto run_next_statement;
      }
      // This is not the loop you are looking for... so Walk back up the stack
      tempsp += sizeof(struct stack_gosub_frame);
      break;
    case STACK_FOR_FLAG:
      // Flag, Var, Final, Step
      if(table_index == KW_NEXT)
      {
        struct stack_for_frame f;
        getStackFrame(tempsp, sizeof( struct stack_for_frame), (unsigned char*)&f);

        // Is the the variable we are looking for?
        if(readMemory(txtpos-1) == f.for_var)
        {
          unsigned int varaddr = variables_table + (readMemory(txtpos-1) - 'A')*VAR_SIZE; 
          int newVar = readMemoryInt(varaddr) + f.step;
          writeMemoryInt(varaddr, newVar);
          // Use a different test depending on the sign of the step increment
          if((f.step > 0 && newVar <= f.terminal) || (f.step < 0 && newVar >= f.terminal))
          {
            // We have to loop so don't pop the stack
            txtpos = f.txtpos;
            current_line = f.current_line;
            goto run_next_statement;
          }
          // We've run to the end of the loop. drop out of the loop, popping the stack
          sp = tempsp + sizeof(struct stack_for_frame);
          goto run_next_statement;
        }
      }
      // This is not the loop you are looking for... so Walk back up the stack
      tempsp += sizeof(struct stack_for_frame);
      break;
    default:
      goto stackstuffed;
    }
  }
  // Didn't find the variable we've been looking for
  goto syntaxerror;

assignment:
  {
    short int value;
    int var;

    if(!isAlphaChar(txtpos))
      goto syntaxerror;
    var = variables_table + ((readMemory(txtpos) - 'A') * VAR_SIZE);
    txtpos++;

    ignore_blanks();

    if (readMemory(txtpos) != '=')
      goto syntaxerror;
    txtpos++;
    ignore_blanks();
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;
    // Check that we are at the end of the statement
    if(!check_statement_end())
      goto syntaxerror;
    writeMemoryInt(var, value);
  }
  goto run_next_statement;

sleep:
  {
    short int value;
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;
    delay(value);
  }
  goto run_next_statement;

dout:
  {
    short int value;
    short int var;
    if(!isDigitChar(txtpos))
      goto syntaxerror;
    var =  readMemory(txtpos) - '0';
    txtpos++;
    ignore_blanks();
    if (readMemory(txtpos) != '=')
      goto syntaxerror;
    txtpos++;
    ignore_blanks();
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;
    // Check that we are at the end of the statement
    if(!check_statement_end())
      goto syntaxerror;

    if( var < 0 || var > 13 )
      goto syntaxerror;
    
    if( !checkAndSetDigitalPin( var, OUTPUT ) )
      goto badporterror;

    if (value == 1)
      digitalWrite(var, HIGH);
    else
      digitalWrite(var, LOW);
  }
  goto run_next_statement;

aout:
  {
    short int value;
    short int var;
    if(!isDigitChar(txtpos))
      goto syntaxerror;
    var =  readMemory(txtpos) - '0';
    txtpos++;
    ignore_blanks();
    if (readMemory(txtpos) != '=')
      goto syntaxerror;
    txtpos++;
    ignore_blanks();
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;

    // Check that we are at the end of the statement
    if(!check_statement_end())
      goto syntaxerror;

    if( !(var == 3 || var == 5 || var == 6 ) )
      goto badporterror;

    // Check digital pin as analog out is PWM on pins 3, 5, 6
    if( !checkAndSetDigitalPin( var, OUTPUT ) ) {
      goto badporterror;
    }      
    analogWrite(var, value);
  }
  goto run_next_statement;

poke:
  {
    short int value;
    unsigned int address;
    unsigned char current_option = table_index;

    // Work out where to put it
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;
    address = (unsigned int)value;

    // check for a comma
    ignore_blanks();
    if (readMemory(txtpos) != ',')
      goto syntaxerror;
    txtpos++;
    ignore_blanks();

    // Now get the value to assign
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;

    if( current_option == KW_POKE ) {
      if( address >= SRAM_START && address <= SRAM_END ) {
        writeMemory( address, value & 0xFF );
      } else {
        goto syntaxerror;
      }
    }
    else
    {
      if( address >= 0 && address < 1024 ) 
        EEPROM.write((int) address, (unsigned char) value);
      else
        goto syntaxerror;
    } 
    // Check that we are at the end of the statement
    if(!check_statement_end())
      goto syntaxerror;
  }
  goto run_next_statement;

list:
  linenum = testnum(); // Retuns 0 if no line found.

  // Should be EOL
  if(!isNLChar(txtpos))
    goto syntaxerror;

  // Find the line
  list_line = findline();
  while(list_line != program_end)
    printline();
  goto warmstart;

#ifdef USESD
save:
  if (!sdcardFitted) {
    printmsgP(sdinitfailmsg);
    goto warmstart;
  }

  setFileName();
/*  ignore_blanks();
  n = 0;
  while(!isNLChar(txtpos) && n<12 ) {
    filename[n++] = readMemory(txtpos++);           
  }
  filename[n] = '\0';
*/
  // open the file.
  if(sdCard.open(filename, O_RDWR | O_CREAT | O_AT_END )) {
    // if the file opened okay, write to it:
    printmsgP( sdfilesaving );
    linenum = testnum(); // Retuns 0 if no line found.
    // Should be EOL
    if(!isNLChar(txtpos))
      goto syntaxerror;

    // Find the line
    list_line = findline();
    while(list_line != program_end)
      printlineSD();

    // close the file:
    sdCard.close();
  } 
  else {
    // if the file didn't open, print an error:
    printmsgP(sdfileerrormsg);
  }        

  goto warmstart;

load:
  if (!sdcardFitted) {
    printmsgP(sdinitfailmsg);
    goto warmstart;
  }

  setFileName();
/*  ignore_blanks();
  n = 0;
  while(!isNLChar(txtpos) && n<12 ) {
    filename[n++] = readMemory(txtpos++);           
  }
  filename[n] = '\0';
*/
load2:
  if(sdCard.open(filename, O_READ )) {
    // if the file opened okay, write to it:
    // Reset program locations
    program_end = program_start;

    char c;
    
    txtpos = program_end+sizeof(LINENUM);
    while((c = sdCard.read()) > 0) {
      switch(c)
      {
        case CR:
        case NL:
          // Terminate all strings with a NL
          writeMemory(txtpos, NL);
          addNewLine();
          txtpos = program_end+sizeof(LINENUM);
          break;
        default:
          // We need to leave at least one space to allow us to shuffle the line into order
          if(txtpos == sp-2)
            outchar(BELL);
          else
          {
            writeMemory(txtpos, c);
            txtpos++;
          }
      }
    }
    // close the file:
    sdCard.close();

  } 
  else {
    // if the file didn't open, print an error:
    printmsgP(sdfileerrormsg);
  }        

  // If this is the LRUN command then auto run else just display prompt
  if( table_index == KW_LRUN ) {
    current_line = program_start;
    goto execline;
  } 
  else {
    goto warmstart;
  }

dirsdcard:
  if (!sdcardFitted) {
    printmsgP(sdinitfailmsg);
    goto warmstart;
  }
  printDirectory();
#endif
  goto warmstart;

servo:
  {
    short int value;
    short int var;
    if(!isDigitChar(txtpos))
      goto syntaxerror;
    var =  readMemory(txtpos) - '0';
    txtpos++;
    ignore_blanks();
    if (readMemory(txtpos) != '=')
      goto syntaxerror;
    txtpos++;
    ignore_blanks();
    expression_error = 0;
    value = expression();
    if(expression_error)
      goto invalidexpr;

    // Check that we are at the end of the statement
    if(!check_statement_end())
      goto syntaxerror;

    if( !(var == 3 || var == 5 || var == 6 ) )
      goto badporterror;

    value = max(0, min(value,179));
    
    servo.attach( var );
    servo.write( value );
  }
  goto run_next_statement;

displaymem:
  printmsgP(freemem);
  printnum(sp-program_end);
  printmsgP(memorymsg);
  // These are here for info only.
/*  Serial.print("txtpos: ");
  Serial.println(txtpos,DEC);
  Serial.print("Program Start: ");
  Serial.println(program_start, DEC);
  Serial.print("Program End: ");
  Serial.println(program_end, DEC);
  Serial.print("Stack Pointer: ");
  Serial.println(sp, DEC);
*/
  goto warmstart;

print:
  // If we have an empty list then just put out a NL
  if(readMemory(txtpos) == ':' )
  {
    line_terminator();
    txtpos++;
    goto run_next_statement;
  }
  if(isNLChar(txtpos) == NL)
  {
    goto execnextline;
  }

  while(1)
  {
    ignore_blanks();
    if(print_quoted_string())
    {
      ;
    }
    else if(readMemory(txtpos) == '"' || readMemory(txtpos) == '\'')
      goto syntaxerror;
    else
    {
      short int e;
      expression_error = 0;
      e = expression();
      if(expression_error)
        goto invalidexpr;
      printnum(e);
    }

    // At this point we have three options, a comma or a new line
    if(readMemory(txtpos) == ',')
      txtpos++;	// Skip the comma and move onto the next
    else if(readMemory(txtpos) == ';' && (isNLChar(txtpos+1) || readMemory(txtpos+1) == ':'))
    {
      txtpos++; // This has to be the end of the print - no newline
      break;
    }
    else if(check_statement_end())
    {
      line_terminator();	// The end of the print statement
      break;
    }
    else
      goto syntaxerror;	
  }
  goto run_next_statement;
}

/***************************************************************************/
static void line_terminator(void)
{
  outchar(NL);
  outchar(CR);
}


/***********************************************************/
static unsigned char breakcheck(void)
{
  if(Serial.available())
    return Serial.read() == CTRLC;
  return 0;
}
/***********************************************************/
static int inchar()
{
  while(1)
  {
    if(Serial.available())
      return Serial.read();
  }
}

/***********************************************************/
static void outchar(unsigned char c)
{
  Serial.write(c);
}


boolean checkAndSetDigitalPin( byte pin, byte state ) {
  // Pin is already set correctly dont reset it
  if( digitalPinMode[pin] == state ) {
    // Already set
    return true;
  }
  // Pin is undefined or usable and this is a change of state
  if( (digitalPinMode[pin] == UNDEFINED) ||
      (digitalPinMode[pin] != state && digitalPinMode[pin] != UNUSED ) ) {
    pinMode( pin, state );
    digitalPinMode[pin] = state;
    return true;
  }

  return false;
}


boolean checkAndSetAnalogPin( byte pin, byte state ) {
  // Pin is already set correctly dont reset it
  if( digitalPinMode[pin] == state ) {
    // Already set
    return true;
  }
  // Pin is undefined or usable and this is a change of state
  if( (analogPinMode[pin] == UNDEFINED) ||
      (analogPinMode[pin] != state && analogPinMode[pin] != UNUSED ) ) {
    pinMode( pin, state );
    analogPinMode[pin] = state;
    return true;
  }

  return false;
}

// Quick funcltion to set a pin to output and make it high to disable a device.
void initCsPin( byte csPin ) {
  pinMode( csPin, OUTPUT);
  digitalWrite( csPin, HIGH );
}

/***********************************************************/
void setup()
{
  // Set various Nanode enable pins for SPI devices
  initCsPin(RFM12B_CS_PIN);
  initCsPin(ENC_CS_PIN);
  initCsPin(SRAM_CS_PIN);
  initCsPin(SDCARD_CS_PIN);
  
  Serial.begin(9600);  // opens serial port, sets data rate to 9600 bps
//  Serial.print("Free RAM: ");
//  Serial.println(freeRam(),DEC);
  
  // Test Sram, if it fails then alternate outputs 5 & 6
  if( !testMemory() ) {
    pinMode(5,OUTPUT);
    pinMode(6,OUTPUT);
    while(1) {
      digitalWrite(5, HIGH);
      digitalWrite(6, LOW);
      delay(200);
      digitalWrite(5, LOW);
      digitalWrite(6, HIGH);
      delay(200);
    }
  }

  clearMemory();
  
#ifdef USESD
  // Detect if we have a uSD card fitted for save/load
  sdcardFitted = true;

  if (!sd.init(SPI_HALF_SPEED,SDCARD_CS_PIN)) {
    sdcardFitted = false;
    // Hack to reset SPI bus speed back to Clock/4 otherwise it gets set to Clock/64
    SPCR = 0x50;
  }
#endif

  // Initialise random seed
  randomSeed(analogRead(0) * analogRead(1) * (int) (getTempFloat() * 1000));
}

/***********************************************************/
// SRAM functions to have program, variables and stack in sram.

void clearMemory() {
  SRAM9.writestream( SRAM_START );
  for( int i = 0; i < (SRAM_END-SRAM_START); i++ )
    SRAM9.RWdata( 0 );
  SRAM9.closeRWstream(); 
}

boolean testMemory() {
  // Write pattern 0x55
  SRAM9.writestream( SRAM_START );
  for( int i = 0; i < (SRAM_END-SRAM_START); i++ )
    SRAM9.RWdata( 0x55 );
  SRAM9.closeRWstream();
  
  // Read back
  SRAM9.readstream( SRAM_START );
  for( int i = 0; i < (SRAM_END-SRAM_START); i++ ) {
    if( SRAM9.RWdata(0xFF) != 0x55 ) {
      SRAM9.closeRWstream();
      return false;
    }
  }
  SRAM9.closeRWstream();
  return true;
}


unsigned char readMemory( unsigned int address ) {
  SRAM9.readstream( address );
  unsigned char ch = SRAM9.RWdata(0xFF);
  SRAM9.closeRWstream();
  return ch;  
}

unsigned int readMemoryInt( unsigned int address ) {
  SRAM9.readstream( address );
  unsigned int val = SRAM9.RWdata(0xFF);
  val += (SRAM9.RWdata(0xFF) << 8);
  SRAM9.closeRWstream();
  return val;  
}

void getStackFrame( unsigned int address, int len, unsigned char *ptr) {
  SRAM9.readstream( address );
  while( len > 0 ) {
    *ptr++ = SRAM9.RWdata(0xFF);
    len--;
  }
  SRAM9.closeRWstream();
}

void writeMemory( unsigned int address, unsigned char val ) {
  SRAM9.writestream( address );
  SRAM9.RWdata( val );
  SRAM9.closeRWstream();
}

void writeMemoryInt( unsigned int address, unsigned int val ) {
  SRAM9.writestream( address );
  SRAM9.RWdata( val & 0xFF );
  SRAM9.RWdata( val >> 8 );
  SRAM9.closeRWstream();
}

void writeStackFrame( unsigned int address, int len, unsigned char *ptr) {
  SRAM9.writestream( address );
  while( len > 0 ) {
    SRAM9.RWdata(*ptr++);
    len--;
  }
  SRAM9.closeRWstream();
}

// Utility functions to save doing multiple SRAM reads
boolean isAlphaChar( int addr ) {
  unsigned char ch = readMemory( addr );
  return( ch >= 'A' && ch <= 'Z');  
}

boolean isLowerChar( int addr ) {
  unsigned char ch = readMemory( addr );
  return( ch >= 'a' && ch <= 'z');  
}

boolean isDigitChar( int addr ) {
  unsigned char ch = readMemory( addr );
  return( ch >= '0' && ch <= '9');  
}

boolean isNLChar( int addr ) {
  return( readMemory( addr ) == NL );
}

#ifdef USESD
void printDirectory() {
  if (!volume.init(sd.card())) {
    printmsgP(sdinitfailmsg);
    sdcardFitted = false;
    return;
  }
  
  if (!root.openRoot(&volume)) {
    return;
  }
  root.ls(LS_DATE | LS_SIZE);
  root.close();
}
#endif

// Common code to read filename from the input buffer
void setFileName() {
  ignore_blanks();
  int n = 0;
  while(!isNLChar(txtpos) && n<12 ) {
    filename[n++] = readMemory(txtpos++);           
  }
  filename[n] = '\0';
}

// Extracted from main code so that it can be re-used by uSD loader
// return value should go to these labels for normal processing and to equivalent in uSD loader
// 0 - no goto, just continue
// 1 - direct
// 2 - badline
// 3 - prompt
int addNewLine() {
  unsigned int start;
  unsigned int newEnd;
  unsigned char linelen;
//  unsigned int tomove;
//  unsigned int from, dest;
//  unsigned int space_to_make;
    
  txtpos = program_end+sizeof(unsigned short);

  // Find the end of the freshly entered line
  while(!isNLChar(txtpos))
    txtpos++;

  // Move it to the end of program_memory
  {
    unsigned int dest;
    dest = sp-1;
    while(1)
    {
      writeMemory(dest, readMemory(txtpos));
      if(txtpos == program_end+sizeof(unsigned short))
        break;
      dest--;
      txtpos--;
    }
    txtpos = dest;
  }

  // Now see if we have a line number
  linenum = testnum();
  ignore_blanks();
  if(linenum == 0)
    return 1;

  if(linenum == 0xFFFF)
    return 2;

  // Find the length of what is left, including the (yet-to-be-populated) line header
  linelen = 0;
  while(!isNLChar(txtpos+linelen))
    linelen++;
  linelen++; // Include the NL in the line length
  linelen += sizeof(unsigned short)+sizeof(char); // Add space for the line number and line length

  // Now we have the number, add the line header.
  txtpos -= 3;
  writeMemoryInt(txtpos, linenum);
  writeMemory(txtpos+sizeof(LINENUM), linelen);

  // Merge it into the rest of the program
  start = findline();

  // If a line with that number exists, then remove it
  if(start != program_end && readMemoryInt(start) == linenum)
  {
    unsigned int dest, from;
    unsigned tomove;

    from = start + readMemory(start+sizeof(LINENUM));
    dest = start;

    tomove = program_end - from;

    while( tomove > 0)
    {
      writeMemory(dest, readMemory( from ) );
      from++;
      dest++;
      tomove--;
    }	
    program_end = dest;
  }

  if(isNLChar(txtpos+sizeof(LINENUM)+sizeof(char))) // If the line has no txt, it was just a delete
    return 3;

  // Make room for the new line, either all in one hit or lots of little shuffles
  while(linelen > 0)
  {	
    unsigned int tomove;
    unsigned int from, dest;
    unsigned int space_to_make;

    space_to_make = txtpos - program_end;

    if(space_to_make > linelen)
      space_to_make = linelen;
    newEnd = program_end+space_to_make;
    tomove = program_end - start;

    // Source and destination - as these areas may overlap we need to move bottom up
    from = program_end;
    dest = newEnd;
    while(tomove > 0)
    {
      from--;
      dest--;
      writeMemory(dest, readMemory( from ) );
      tomove--;
    }

    // Copy over the bytes into the new space
    for(tomove = 0; tomove < space_to_make; tomove++)
    {
      writeMemory(start, readMemory(txtpos));
      txtpos++;
      start++;
      linelen--;
    }
    program_end = newEnd;
  }

  return 0;
}

/**********************************************************/
// Extra functions added for grins.

int getTempInt() {
	int result = (int) (getTempFloat() + 0.5);
	return result;
}

float getTempFloat() {
  float result;
  int res;
  static uint8_t saveADMUX, saveADCSRA;
  saveADMUX = ADMUX;
  saveADCSRA = ADCSRA;
  // Read temperature sensor against 1.1V reference
  ADMUX = _BV(REFS1) | _BV(REFS0) | _BV(MUX3);
  delay(10); // Wait for Vref to settle
  ADCSRA |= _BV(ADSC); // Convert
  while (bit_is_set(ADCSRA,ADSC));
  res = ADCL;
  res |= ADCH<<8;
  result = (float) res;
  //result = ((result - 125) * 1075)/10;
  result = ((result - 336.59) / 1.17);
  ADMUX = saveADMUX;
  ADCSRA = saveADCSRA;
  return result;
}

// Thats All Folks!
