/* Minimal Palm OS declarations so clang can parse Space Trader for the
   transpiler (tools/transpile.py). Only types and prototypes; the Odin
   implementations live in src/game/palm*.odin. */
#ifndef PALMOS_STUB_H
#define PALMOS_STUB_H
typedef char Byte;
typedef unsigned char UInt8;
typedef signed char Int8;
typedef unsigned short UInt16;
typedef unsigned short Word;
typedef unsigned short UInt;
typedef short Int16;
typedef short SWord;
typedef short Coord;
typedef unsigned long UInt32;
typedef unsigned long DWord;
typedef unsigned long ULong;
typedef long Int32;
typedef unsigned short WChar;
typedef char Char;
typedef char* CharPtr;
typedef _Bool Boolean;
typedef UInt16 Err;
typedef void* VoidPtr;
typedef void* Ptr;
typedef struct OpaqueHandle* MemHandle;
typedef MemHandle Handle;
typedef MemHandle VoidHand;
typedef void* MemPtr;
typedef UInt32 LocalID;
typedef struct OpaqueDmOpen* DmOpenRef;
typedef struct OpaqueForm FormType;
typedef FormType* FormPtr;
typedef struct OpaqueControl { struct { int frame; } attr; } ControlType;
typedef ControlType* ControlPtr;
typedef struct OpaqueField FieldType;
typedef FieldType* FieldPtr;
typedef struct OpaqueList ListType;
typedef ListType* ListPtr;
typedef struct OpaqueBitmap { Coord width; Coord height; } BitmapType;
typedef BitmapType* BitmapPtr;
typedef struct { Coord x; Coord y; } PointType;
typedef struct { PointType topLeft; PointType extent; } RectangleType;
typedef RectangleType* RectanglePtr;
typedef enum { nilEvent = 0, penDownEvent, penUpEvent, penMoveEvent, keyDownEvent, winEnterEvent,
	winExitEvent, ctlEnterEvent, ctlExitEvent, ctlSelectEvent, ctlRepeatEvent, lstEnterEvent,
	lstSelectEvent, lstExitEvent, popSelectEvent, fldEnterEvent, fldHeightChangedEvent,
	fldChangedEvent, tblEnterEvent, tblSelectEvent, daySelectEvent, menuEvent, appStopEvent,
	frmLoadEvent, frmOpenEvent, frmGotoEvent, frmUpdateEvent, frmSaveEvent, frmCloseEvent,
	frmTitleEnterEvent, frmTitleSelectEvent } eventsEnum;
typedef struct {
	eventsEnum eType;
	Boolean penDown;
	Int16 tapCount;
	Int16 screenX;
	Int16 screenY;
	struct {
		struct { UInt16 controlID; ControlPtr pControl; Boolean on; } ctlSelect;
		struct { WChar chr; UInt16 keyCode; UInt16 modifiers; } keyDown;
		struct { UInt16 itemID; } menu;
		struct { UInt16 formID; } frmLoad;
		struct { UInt16 formID; } frmOpen;
		struct { UInt16 formID; UInt16 updateCode; } frmUpdate;
		struct { UInt16 controlID; ControlPtr controlP; ListPtr listP; Int16 selection; Int16 priorSelection; } popSelect;
		struct { UInt16 listID; ListPtr pList; Int16 selection; } lstSelect;
	} data;
} EventType;
typedef EventType* EventPtr;
typedef Boolean FormEventHandlerType(EventType* eventP);
typedef struct { Int16 second, minute, hour, day, month, year, weekDay; } DateTimeType;
typedef DateTimeType* DateTimePtr;
typedef enum { stdFont = 0, boldFont, largeFont, symbolFont, symbol11Font, symbol7Font, ledFont, largeBoldFont } FontID;
typedef enum { winPaint, winErase, winMask, winInvert, winOverlay, winPaintInverse, winSwap } WinDrawOperation;
typedef enum { noFrame = 0, standardButtonFrame, boldButtonFrame, rectangleButtonFrame } ButtonFrameType;
enum { evtWaitForever = -1, noPreferenceFound = -1, errNone = 0, sysErrRomIncompatible = 0x0501,
	sysAppLaunchCmdNormalLaunch = 0, sysAppLaunchFlagNewGlobals = 4, sysAppLaunchFlagUIApp = 8,
	sysFtrCreator = 0x70737973, sysFtrNumROMVersion = 1, bitmapRsc = 0x54626d70, dmModeReadWrite = 3,
	dmModeReadOnly = 1, dmHdrAttrBackup = 8, sysFileCDefaultApp = 0, sysROMStageRelease = 3,
	chrPageUp = 0x0B, chrPageDown = 0x0C, vchrHard1 = 0x0204, vchrHard2 = 0x0205, vchrHard3 = 0x0206,
	vchrHard4 = 0x0207, hard1Chr = 0x0204, hard2Chr = 0x0205, hard3Chr = 0x0206, hard4Chr = 0x0207,
	grfTempShiftUpper = 2, winScreenModeGetSupportsColor = 0, winScreenModeGetSupportedDepths = 1,
	winScreenModeSet = 2, winScreenModeSetToDefaults = 3, appFileCreator = 0x53547261, appPrefID = 0 };
#define sysMakeROMVersion(major, minor, fix, stage, buildNum) \
	((((UInt32)(major)) << 24) | (((UInt32)(minor)) << 16) | (((UInt32)(fix)) << 12) | (((UInt32)(stage)) << 8) | ((UInt32)(buildNum)))
#define NULL ((void*)0)
#define true 1
#define false 0

/* Strings */
Char* StrCopy(Char* dst, const Char* src);
Char* StrNCopy(Char* dst, const Char* src, Int16 n);
Char* StrCat(Char* dst, const Char* src);
Int16 StrLen(const Char* src);
Char* StrIToA(Char* s, Int32 i);
Int32 StrAToI(const Char* str);
Int16 StrCompare(const Char* s1, const Char* s2);
Int16 StrNCompare(const Char* s1, const Char* s2, Int32 n);
Int16 StrCaselessCompare(const Char* s1, const Char* s2);
Char* StrToLower(Char* dst, const Char* src);
Int16 StrPrintF(Char* s, const Char* formatStr, ...);
Char* SysStringByIndex(UInt16 resID, UInt16 index, Char* strP, UInt16 maxLen);
void SysCopyStringResource(Char* string, Int16 theID);

/* Forms */
UInt16 FrmAlert(UInt16 alertId);
UInt16 FrmCustomAlert(UInt16 alertId, const Char* s1, const Char* s2, const Char* s3);
UInt16 FrmGetObjectIndex(const FormType* formP, UInt16 objID);
void* FrmGetObjectPtr(const FormType* formP, UInt16 objIndex);
void FrmShowObject(FormType* formP, UInt16 objIndex);
void FrmHideObject(FormType* formP, UInt16 objIndex);
void FrmGotoForm(UInt16 formId);
FormType* FrmGetActiveForm(void);
UInt16 FrmGetActiveFormID(void);
void FrmSetActiveForm(FormType* formP);
void FrmDrawForm(FormType* formP);
void FrmHelp(UInt16 helpMsgId);
FormType* FrmInitForm(UInt16 rscID);
UInt16 FrmDoDialog(FormType* formP);
void FrmDeleteForm(FormType* formP);
void FrmSetEventHandler(FormType* formP, FormEventHandlerType* handler);
void FrmSetTitle(FormType* formP, Char* newTitle);
void FrmCopyTitle(FormType* formP, const Char* newTitle);
const Char* FrmGetTitle(const FormType* formP);
void FrmSetFocus(FormType* formP, UInt16 fieldIndex);
FormType* FrmGetFormPtr(UInt16 formId);
void FrmCopyLabel(FormType* formP, UInt16 labelID, const Char* newLabel);
void FrmCloseAllForms(void);
Boolean FrmHandleEvent(FormType* formP, EventType* eventP);
Boolean FrmDispatchEvent(EventType* eventP);
void FrmSetMenu(FormType* formP, UInt16 menuRscID);
void FldSetTextHandle(FieldType* fldP, MemHandle textHandle);
void CtlSetLabel(ControlType* controlP, const Char* newLabel);
const Char* CtlGetLabel(const ControlType* controlP);
void CtlSetValue(ControlType* controlP, Int16 newValue);
Int16 CtlGetValue(const ControlType* controlP);
void CtlDrawControl(ControlType* controlP);
void CtlShowControl(ControlType* controlP);
void LstSetSelection(ListType* listP, Int16 itemNum);
Int16 LstGetSelection(const ListType* listP);
void MenuEraseStatus(void* menuP);
Boolean MenuHandleEvent(void* menuP, EventType* event, UInt16* error);
Boolean SysHandleEvent(EventPtr eventP);
void EvtGetEvent(EventType* event, Int32 timeout);
void EvtAddEventToQueue(const EventType* event);
void GrfSetState(Boolean capsLock, Boolean numLock, Boolean upperShift);

/* Drawing */
FontID FntSetFont(FontID font);
Int16 FntCharsWidth(const Char* chars, Int16 len);
Int16 FntLineHeight(void);
void FntCharsInWidth(const Char* string, Int16* stringWidthP, Int16* stringLengthP, Boolean* fitWithinWidth);
void WinDrawChars(const Char* chars, Int16 len, Coord x, Coord y);
void WinDrawInvertedChars(const Char* chars, Int16 len, Coord x, Coord y);
void WinDrawLine(Coord x1, Coord y1, Coord x2, Coord y2);
void WinEraseLine(Coord x1, Coord y1, Coord x2, Coord y2);
void WinDrawRectangle(const RectangleType* rP, UInt16 cornerDiam);
void WinEraseRectangle(const RectangleType* rP, UInt16 cornerDiam);
void WinDrawRectangleFrame(UInt16 frame, const RectangleType* rP);
void WinDrawBitmap(BitmapPtr bitmapP, Coord x, Coord y);
void WinSetClip(const RectangleType* rP);
void WinResetClip(void);
Err WinScreenMode(int op, UInt32* widthP, UInt32* heightP, UInt32* depthP, Boolean* enableColorP);
void BmpGetDimensions(const BitmapType* bitmapP, Coord* widthP, Coord* heightP, UInt16* rowBytesP);

/* Memory, resources, databases, prefs */
MemHandle MemHandleNew(UInt32 size);
MemPtr MemHandleLock(MemHandle h);
Err MemHandleUnlock(MemHandle h);
Err MemPtrUnlock(MemPtr p);
Err MemHandleFree(MemHandle h);
Err MemMove(void* dstP, const void* sP, Int32 numBytes);
Err MemSet(void* dstP, Int32 numBytes, UInt8 value);
MemHandle DmGetResource(UInt32 type, UInt16 resID);
Err DmReleaseResource(MemHandle resourceH);
LocalID DmFindDatabase(UInt16 cardNo, const Char* nameP);
DmOpenRef DmOpenDatabase(UInt16 cardNo, LocalID dbID, UInt16 mode);
Err DmCloseDatabase(DmOpenRef dbP);
Err DmCreateDatabase(UInt16 cardNo, const Char* nameP, UInt32 creator, UInt32 type, Boolean resDB);
MemHandle DmGetRecord(DmOpenRef dbP, UInt16 index);
MemHandle DmNewRecord(DmOpenRef dbP, UInt16* atP, UInt32 size);
Err DmReleaseRecord(DmOpenRef dbP, UInt16 index, Boolean dirty);
Err DmWrite(void* recordP, UInt32 offset, const void* srcP, UInt32 bytes);
Err DmDatabaseInfo(UInt16 cardNo, LocalID dbID, Char* nameP, UInt16* attributesP, UInt16* versionP,
	UInt32* crDateP, UInt32* modDateP, UInt32* bckUpDateP, UInt32* modNumP, LocalID* appInfoIDP,
	LocalID* sortInfoIDP, UInt32* typeP, UInt32* creatorP);
Err DmSetDatabaseInfo(UInt16 cardNo, LocalID dbID, const Char* nameP, UInt16* attributesP, UInt16* versionP,
	UInt32* crDateP, UInt32* modDateP, UInt32* bckUpDateP, UInt32* modNumP, LocalID* appInfoIDP,
	LocalID* sortInfoIDP, UInt32* typeP, UInt32* creatorP);
Err DmOpenDatabaseInfo(DmOpenRef dbP, LocalID* dbIDP, UInt16* openCountP, UInt16* modeP, UInt16* cardNoP, Boolean* resDBP);
Int16 PrefGetAppPreferences(UInt32 creator, UInt16 id, void* prefs, UInt16* prefsSize, Boolean saved);
void PrefSetAppPreferences(UInt32 creator, UInt16 id, Int16 version, const void* prefs, UInt16 prefsSize, Boolean saved);
Err FtrGet(UInt32 creator, UInt16 featureNum, UInt32* valueP);
UInt32 TimGetTicks(void);
UInt32 TimGetSeconds(void);
UInt32 TimDateTimeToSeconds(DateTimePtr dateTimeP);
UInt16 SysTicksPerSecond(void);
Int16 SysRandom(Int32 newSeed);
Err AppLaunchWithCommand(UInt32 dbType, UInt16 launchCode, void* commandPBP);
#endif
