#!/usr/bin/env python3
"""Transpile the Space Trader 1.2.2 C sources to Odin.

Pipeline (Python stdlib plus the `clang` binary):
  1. copy reference/Src to build/csrc, turn numeric #defines in spacetrader.h
     into enum constants (so names survive into the AST) and apply the small
     PATCHES below;
  2. run `clang -Xclang -ast-dump=json` on every .c file with the Palm OS stub
     headers in tools/palm_stub;
  3. walk the AST and write src/game/st_<file>.odin.

The C code keeps its shape: every function, global and table keeps its C name.
Mutable globals become fields of the `Globals` struct (`g.Name`), so the Palm
runtime can snapshot and restore the whole game state (see palm_run.odin).
Functions listed in OVERRIDES are hand-written in Odin instead.

Run from the repo root:  python3 -I tools/transpile.py
"""
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "reference", "Src")
CSRC = os.path.join(ROOT, "build", "csrc")
STUB = os.path.join(ROOT, "tools", "palm_stub")
OUT = os.path.join(ROOT, "src", "game")

# Functions written by hand in Odin (palm_*.odin or game_*.odin).
OVERRIDES = {
    "GetBitmapWidth", "GetBitmapHeight", "GraphicsSupport", "EndGraphicsSupport",
    "RomVersionCompatible", "OutdatedSoftware", "AppEventLoop", "MerchantPilotMain",
    "PilotMain", "AppStop", "RectangularButton", "sqrt",
}

# Source patches applied to the build copy before parsing: (file, old, new).
PATCHES = [
    # Clicks counts parsecs down to arrival; Palm's Boolean is a byte, ours is bool.
    ("Global.c", "Boolean Clicks = 0;", "Byte Clicks = 0;"),
    ("DataTypes.h", "Boolean Clicks;", "Byte Clicks;"),
    ("external.h", "extern Boolean Clicks;", "extern Byte Clicks;"),
    ("WarpFormEvent.c", "static void DrawShortRange", "void DrawShortRange"),
    ("WarpFormEvent.c", "static void DrawCircle", "void DrawCircle"),
    ("WarpFormEvent.c", "static void DrawGalaxy", "void DrawGalaxy"),
    ("SystemInfoEvent.c", "static void DrawPersonnelRoster", "void DrawPersonnelRoster"),
]

ODIN_KEYWORDS = {
    "proc", "map", "in", "not_in", "context", "cast", "transmute", "distinct", "dynamic", "struct",
    "union", "enum", "bit_set", "matrix", "defer", "when", "where", "or_else", "or_return",
    "foreign", "import", "package", "using", "auto_cast", "typeid", "string", "rune", "len", "cap",
    "fallthrough", "switch", "case", "if", "else", "for", "do", "return", "break", "continue",
    "nil", "true", "false", "size_of", "min", "max", "abs", "byte", "int", "uint", "b8", "any",
}

SCALARS = {
    "int": "i32", "long": "i32", "unsigned long": "u32", "unsigned int": "u32", "short": "i16",
    "unsigned short": "u16", "char": "u8", "unsigned char": "u8", "signed char": "i8",
    "_Bool": "bool", "long long": "i64", "unsigned long long": "u64", "void": "void",
    "double": "f64", "float": "f32",
}
# Palm typedefs that should keep a named Odin type (opaque handles, events).
NAMED = {
    "FormType": "FormType", "ControlType": "ControlType", "FieldType": "FieldType",
    "ListType": "ListType", "BitmapType": "BitmapType", "EventType": "EventType",
    "RectangleType": "RectangleType", "PointType": "PointType", "DateTimeType": "DateTimeType",
    "struct OpaqueHandle": "OpaqueHandle", "struct OpaqueDmOpen": "OpaqueDmOpen",
    "struct OpaqueForm": "FormType", "struct OpaqueControl": "ControlType",
    "struct OpaqueField": "FieldType", "struct OpaqueList": "ListType",
    "struct OpaqueBitmap": "BitmapType",
}
TYPEDEF_DESUGAR = {}
FUNC_RETURNS = {}  # function name -> return ctype, from the definitions  # filled from the AST: typedef name -> underlying qualType


class Fail(Exception):
    pass


# ---------------------------------------------------------------- types

def strip_quals(t):
    t = t.strip()
    t = re.sub(r"\b(const|volatile|struct)\s+", lambda m: "" if m.group(1) != "struct" else "struct ", t)
    return t.strip()


def resolve_typedef(t):
    seen = 0
    while t in TYPEDEF_DESUGAR and seen < 10:
        t = TYPEDEF_DESUGAR[t]
        seen += 1
    return t


RECORDS = {}  # record typedef name -> list of (field, qualType)


def ctype(t):
    """Return a structured C type: ('scalar', odin) | ('ptr', inner) | ('array', n, inner)
    | ('record', name) | ('func',) | ('named', odin)."""
    t = t.strip()
    t = re.sub(r"\bconst\b", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    m = re.match(r"^([^\[]*)\[(\d*)\](.*)$", t)
    if m and "(" not in m.group(1):
        inner = (m.group(1).strip() + " " + m.group(3).strip()).strip()
        n = m.group(2)
        return ("array", int(n) if n else 0, ctype(inner))
    if t.endswith("*"):
        inner = t[:-1].strip()
        if "(" in inner:
            return ("ptr", ("func",))
        return ("ptr", ctype(inner))
    if "(" in t:
        return ("func",)
    if t in NAMED:
        return ("named", NAMED[t])
    if t in RECORDS:
        return ("record", t)
    if t in SCALARS:
        return ("scalar", SCALARS[t])
    if t.startswith("enum") or t in ("eventsEnum", "FontID", "WinDrawOperation", "ButtonFrameType"):
        return ("scalar", "i32")
    if t.startswith("struct "):
        n = t[7:]
        if n in RECORDS:
            return ("record", n)
    r = resolve_typedef(t)
    if r != t:
        if t in NAMED:
            return ("named", NAMED[t])
        return ctype(r)
    raise Fail("unknown type %r" % t)


def odin_type(ct):
    k = ct[0]
    if k == "scalar":
        return ct[1]
    if k == "named":
        return ct[1]
    if k == "record":
        return ct[1]
    if k == "array":
        return "[%d]%s" % (ct[1], odin_type(ct[2]))
    if k == "ptr":
        inner = ct[1]
        if inner[0] == "scalar" and inner[1] == "u8":
            return "cstring"
        if inner[0] == "scalar" and inner[1] == "void":
            return "rawptr"
        if inner[0] == "func":
            return "FormEventHandlerType"
        if inner[0] == "scalar":
            return "[^]%s" % inner[1]
        if inner[0] == "named" and inner[1] == "OpaqueHandle":
            return "MemHandle"
        if inner[0] == "named" and inner[1] == "OpaqueDmOpen":
            return "DmOpenRef"
        return "^%s" % odin_type(inner)
    if k == "func":
        return "FormEventHandlerType"
    raise Fail("odin_type %r" % (ct,))


def is_char_ptr(ct):
    return ct[0] == "ptr" and ct[1][0] == "scalar" and ct[1][1] == "u8"


def is_scalar_ptr(ct):
    return ct[0] == "ptr" and ct[1][0] == "scalar" and ct[1][1] not in ("u8", "void")


def is_bool(ct):
    return ct[0] == "scalar" and ct[1] == "bool"


def is_int(ct):
    return ct[0] == "scalar" and ct[1] not in ("bool", "void")


def qt(node):
    t = node.get("type", {})
    return t.get("qualType", "")


def nct(node):
    return ctype(qt(node))


# ---------------------------------------------------------------- AST

def dump_ast(cfile):
    cmd = ["clang", "-std=gnu89", "-w", "-DBPP1", "-funsigned-char", "-I", STUB,
           "-Xclang", "-ast-dump=json", "-fsyntax-only", cfile]
    out = subprocess.run(cmd, capture_output=True, cwd=CSRC)
    if out.returncode != 0:
        sys.stderr.write(out.stderr.decode())
        raise Fail("clang failed on %s" % cfile)
    return json.loads(out.stdout)


def top_decls_with_file(ast):
    cur = None
    for d in ast.get("inner", []):
        loc = d.get("loc", {})
        f = loc.get("file") or loc.get("expansionLoc", {}).get("file") or loc.get("spellingLoc", {}).get("file")
        if f is None:
            rb = d.get("range", {}).get("begin", {})
            f = rb.get("file") or rb.get("expansionLoc", {}).get("file")
        if f:
            cur = f
        yield cur, d


# ---------------------------------------------------------------- emitter

class Ctx:
    def __init__(self, globals_set, funcs, static_map):
        self.globals = globals_set      # names of mutable globals (go to g.)
        self.funcs = funcs              # function name -> (ret ct, [param ct])
        self.static_map = static_map    # (func, local) -> global field name
        self.func = None
        self.ret = None
        self.locals = set()
        self.tmp = 0


def ident(name):
    if name in ODIN_KEYWORDS:
        return name + "_"
    return name


class Emitter:
    def __init__(self, ctx):
        self.c = ctx

    # ---- expressions: return (code, kind) where kind is 'bool' or 'val'
    def expr(self, n):
        k = n["kind"]
        fn = getattr(self, "e_" + k, None)
        if fn is None:
            raise Fail("expr kind %s" % k)
        code, kind = fn(n)
        if kind == "val":
            try:
                if is_bool(nct(n)):
                    kind = "bool"
            except Fail:
                pass
        return code, kind

    def val(self, n):
        code, kind = self.expr(n)
        if kind == "bool":
            return "b2i(%s)" % code
        return code

    def lval(self, n):
        """Code for n as an lvalue / raw value (no bool-to-int wrapping)."""
        return self.expr(n)[0]

    def cond(self, n):
        """Emit n as an Odin bool."""
        if n["kind"] in ("IntegerLiteral", "CharacterLiteral"):
            return "true" if int(n["value"]) != 0 else "false"
        if n["kind"] == "ImplicitCastExpr" and n["castKind"] == "IntegralCast":
            code, kind = self.expr(n["inner"][0])
            if kind == "bool":
                return code
        code, kind = self.expr(n)
        if kind == "bool":
            return code
        ct = nct(n)
        if ct[0] == "ptr":
            return "(%s != nil)" % code
        return "(%s != 0)" % code

    def e_ConstantExpr(self, n):
        return self.expr(n["inner"][0])

    def e_FloatingLiteral(self, n):
        v = n["value"]
        if "." not in v and "e" not in v.lower():
            v += ".0"
        return v, "val"

    def e_ParenExpr(self, n):
        code, kind = self.expr(n["inner"][0])
        if code.startswith("(") and code.endswith(")") and self.balanced(code[1:-1]):
            return code, kind
        return "(%s)" % code, kind

    def e_IntegerLiteral(self, n):
        return n["value"], "val"

    def e_CharacterLiteral(self, n):
        v = n["value"]
        return str(v), "val"

    def e_StringLiteral(self, n):
        return self.strlit(n["value"]), "val"

    def strlit(self, v):
        # v is a C string literal including quotes, as clang prints it
        s = v
        s = s.replace("\\'", "'")
        # octal escapes are not Odin escapes; convert \NNN to \xHH
        s = re.sub(r"\\([0-7]{1,3})", lambda m: "\\x%02x" % int(m.group(1), 8), s)
        return s

    def e_DeclRefExpr(self, n):
        d = n["referencedDecl"]
        name = d["name"]
        dk = d["kind"]
        if dk == "EnumConstantDecl":
            return ident(name), "val"
        if dk == "FunctionDecl":
            return ident(name), "val"
        if dk == "VarDecl":
            key = (self.c.func, name)
            if key in self.c.static_map:
                return "g.%s" % self.c.static_map[key], "val"
            if name in self.c.locals:
                return ident(name), "val"
            if name in self.c.globals:
                return "g.%s" % name, "val"
            return ident(name), "val"
        if dk == "ParmVarDecl":
            return ident(name), "val"
        raise Fail("declref %s" % dk)

    def e_ImplicitCastExpr(self, n):
        ck = n["castKind"]
        inner = n["inner"][0]
        to = nct(n)
        if ck in ("LValueToRValue", "NoOp", "FunctionToPointerDecay", "ToVoid"):
            return self.expr(inner)
        if ck == "ArrayToPointerDecay":
            return self.decay(inner, to), "val"
        if ck == "IntegralToBoolean":
            return self.cond(inner), "bool"
        if ck == "PointerToBoolean":
            return "(%s != nil)" % self.val(inner), "bool"
        if ck == "NullToPointer":
            return "nil", "val"
        if ck in ("IntegralCast", "BooleanToSignedIntegral"):
            return self.convert(inner, to), "val"
        if ck in ("IntegralToFloating", "FloatingToIntegral", "FloatingCast"):
            return "%s(%s)" % (odin_type(to), self.val(inner)), "val"
        if ck == "BitCast":
            return self.ptrcast(inner, to), "val"
        if ck == "IntegralToPointer":
            return "nil", "val"
        raise Fail("implicit cast %s" % ck)

    def decay(self, inner, to):
        ict = nct(inner)
        if inner["kind"] == "StringLiteral":
            return self.strlit(inner["value"])
        code = self.val(inner)
        if is_char_ptr(to):
            return "cstring(&%s[0])" % code
        if is_scalar_ptr(to):
            return "([^]%s)(&%s[0])" % (to[1][1], code)
        return "&%s[0]" % code

    def ptrcast(self, inner, to):
        code = self.val(inner)
        ot = odin_type(to)
        ict = nct(inner)
        if odin_type(ict) == ot:
            return code
        if ot == "cstring":
            return "cstring(cast([^]u8)(%s))" % code
        if odin_type(ict) == "cstring":
            return "cast(%s)(rawptr(%s))" % (ot, code)
        return "cast(%s)(%s)" % (ot, code)

    def convert(self, inner, to):
        """Value of `inner` converted to C type `to` (an integral or bool type)."""
        code, kind = self.expr(inner)
        ot = odin_type(to)
        if ot == "bool":
            if kind == "bool":
                return code
            if inner["kind"] in ("IntegerLiteral", "CharacterLiteral"):
                return "true" if int(inner["value"]) != 0 else "false"
            return "(%s != 0)" % code
        if kind == "bool":
            return "%s(b2i(%s))" % (ot, code) if ot != "i32" else "b2i(%s)" % code
        try:
            it = odin_type(nct(inner))
        except Fail:
            it = None
        if it == ot:
            return code
        if inner["kind"] in ("IntegerLiteral", "CharacterLiteral"):
            v = int(inner["value"]) if inner["kind"] == "IntegerLiteral" else int(inner["value"])
            return "%s(%s)" % (ot, self.wrap_const(v, ot))
        if it == "bool":
            return "%s(b2i(%s))" % (ot, code)
        return "%s(%s)" % (ot, code)

    def wrap_const(self, v, ot):
        bits = {"u8": 8, "i8": 8, "u16": 16, "i16": 16, "u32": 32, "i32": 32}.get(ot)
        if bits is None:
            return str(v)
        mask = (1 << bits) - 1
        v &= mask
        if ot.startswith("i") and v >= (1 << (bits - 1)):
            v -= (1 << bits)
        return str(v)

    def e_CStyleCastExpr(self, n):
        inner = n["inner"][0]
        to = nct(n)
        ck = n["castKind"]
        if to[0] == "scalar" and to[1] == "void":
            return self.val(inner), "val"
        if ck in ("NoOp", "LValueToRValue"):
            return self.expr(inner)
        if ck == "IntegralToBoolean":
            return self.cond(inner), "bool"
        if ck in ("IntegralCast", "BooleanToSignedIntegral"):
            return self.convert(inner, to), "val"
        if ck in ("IntegralToFloating", "FloatingToIntegral", "FloatingCast"):
            return "%s(%s)" % (odin_type(to), self.val(inner)), "val"
        if ck == "BitCast":
            return self.ptrcast(inner, to), "val"
        if ck == "NullToPointer":
            return "nil", "val"
        if ck == "ArrayToPointerDecay":
            return self.decay(inner, to), "val"
        if ck == "IntegralToPointer":
            return "nil", "val"
        if ck == "PointerToIntegral":
            return "0", "val"
        raise Fail("cstyle cast %s" % ck)

    def e_UnaryOperator(self, n):
        op = n["opcode"]
        inner = n["inner"][0]
        if op == "!":
            return "!%s" % self.paren_cond(inner), "bool"
        if op == "-":
            return "-%s" % self.val(inner), "val"
        if op == "+":
            return self.val(inner), "val"
        if op == "~":
            return "~%s" % self.val(inner), "val"
        if op == "&":
            code = self.lval(inner)
            to = nct(n)
            if is_scalar_ptr(to):
                return "([^]%s)(&%s)" % (to[1][1], code), "val"
            if is_char_ptr(to):
                return "cstring(&%s)" % code, "val"
            return "&%s" % code, "val"
        if op == "*":
            ict = nct(inner)
            code = self.val(inner)
            if is_scalar_ptr(ict) or is_char_ptr(ict):
                if is_char_ptr(ict):
                    return "cidx(%s)[0]" % code, "val"
                return "%s[0]" % code, "val"
            return "%s^" % code, "val"
        if op in ("++", "--"):
            code = self.lval(inner)
            post = n.get("isPostfix", False)
            helper = ("post_" if post else "pre_") + ("inc" if op == "++" else "dec")
            return "%s(&%s)" % (helper, code), "val"
        raise Fail("unary %s" % op)

    def paren_cond(self, n):
        c = self.cond(n)
        if re.match(r"^[\w.\[\]]+$", c) or (c.startswith("(") and c.endswith(")") and self.balanced(c[1:-1])):
            return c
        return "(%s)" % c

    @staticmethod
    def balanced(s):
        d = 0
        for ch in s:
            if ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
                if d < 0:
                    return False
        return d == 0

    def e_BinaryOperator(self, n):
        op = n["opcode"]
        a, b = n["inner"]
        if op in ("&&", "||"):
            return "(%s %s %s)" % (self.cond(a), op, self.cond(b)), "bool"
        if op in ("==", "!=", "<", ">", "<=", ">="):
            act, bct = nct(a), nct(b)
            ac, bc = self.cmp_operand(a), self.cmp_operand(b)
            return "(%s %s %s)" % (ac, op, bc), "bool"
        if op == "=":
            return "assign(&%s, %s)" % (self.lval(a), self.assign_rhs(a, b)), ("bool" if is_bool(nct(a)) else "val")
        if op == ",":
            raise Fail("comma operator")
        if op in ("<<", ">>"):
            bc = self.val(b)
            if b["kind"] != "IntegerLiteral":
                bc = "uint(%s)" % bc
            return "(%s %s %s)" % (self.val(a), op, bc), "val"
        if op in ("+", "-") and nct(n)[0] == "ptr":
            # pointer arithmetic: only char* is used in Space Trader
            if is_char_ptr(nct(n)):
                return "cadd(%s, %s%s)" % (self.val(a), "-" if op == "-" else "", self.val(b)), "val"
            raise Fail("pointer arithmetic")
        return "(%s %s %s)" % (self.val(a), op, self.val(b)), "val"

    def cmp_operand(self, n):
        code, kind = self.expr(n)
        if kind == "bool":
            return "b2i(%s)" % code
        return code

    def assign_rhs(self, lhs, rhs):
        lct = nct(lhs)
        if is_bool(lct):
            return self.cond(rhs)
        if lct[0] == "array":
            return self.val(rhs)
        return self.val(rhs)

    def e_CompoundAssignOperator(self, n):
        op = n["opcode"]
        a, b = n["inner"]
        lt = odin_type(nct(a))
        comp = n.get("computeResultType", {}).get("qualType")
        lhs = self.lval(a)
        rhs = self.val(b)
        bop = op[:-1]
        if bop in ("<<", ">>") and b["kind"] != "IntegerLiteral":
            rhs = "uint(%s)" % rhs
        if comp and odin_type(ctype(comp)) != lt:
            ctp = odin_type(ctype(comp))
            return "assign(&%s, %s(%s(%s) %s %s))" % (lhs, lt, ctp, lhs, bop, rhs), "val"
        return "compound_%s(&%s, %s)" % (OPNAMES[bop], lhs, rhs), "val"

    def e_ConditionalOperator(self, n):
        c, a, b = n["inner"]
        to = nct(n)
        if is_bool(to):
            return "(%s ? %s : %s)" % (self.cond(c), self.cond(a), self.cond(b)), "bool"
        return "(%s ? %s : %s)" % (self.cond(c), self.val(a), self.val(b)), "val"

    def e_CallExpr(self, n):
        callee = n["inner"][0]
        args = n["inner"][1:]
        name = self.val(callee)
        out = []
        for a in args:
            out.append(self.cond(a) if is_bool(nct(a)) else self.val(a))
        kind = "bool" if is_bool(nct(n)) else "val"
        rt = FUNC_RETURNS.get(name)
        if rt is not None and is_bool(rt):
            kind = "bool"
        return "%s(%s)" % (name, ", ".join(out)), kind

    def e_MemberExpr(self, n):
        base = n["inner"][0]
        code = self.lval(base)
        return "%s.%s" % (code, n["name"]), ("val")

    def e_ArraySubscriptExpr(self, n):
        base, idx = n["inner"]
        bct = nct(base)
        bcode = self.val(base)
        icode = self.val(idx)
        # base is usually ArrayToPointerDecay of an array; undo the decay
        if base["kind"] == "ImplicitCastExpr" and base["castKind"] == "ArrayToPointerDecay":
            arr = base["inner"][0]
            return "%s[%s]" % (self.lval(arr), icode), "val"
        if is_char_ptr(bct):
            return "cidx(%s)[%s]" % (bcode, icode), "val"
        return "%s[%s]" % (bcode, icode), "val"

    def e_UnaryExprOrTypeTraitExpr(self, n):
        if n["name"] == "sizeof":
            st = odin_type(nct(n))
            if "argType" in n:
                return "%s(size_of(%s))" % (st, odin_type(ctype(n["argType"]["qualType"]))), "val"
            return "%s(size_of(%s))" % (st, self.lval(n["inner"][0])), "val"
        raise Fail("trait %s" % n["name"])

    def e_InitListExpr(self, n):
        items = [self.init_item(x, None) for x in n.get("inner", [])]
        return "{%s}" % ", ".join(items), "val"

    def init_item(self, x, ct):
        if x["kind"] == "ImplicitValueInitExpr":
            return "{}"
        if x["kind"] == "InitListExpr":
            return self.e_InitListExpr(x)[0]
        xct = nct(x)
        if is_bool(xct):
            return self.cond(x)
        return self.val(x)

    # ---- statements
    def stmt(self, n, out, ind):
        k = n["kind"]
        fn = getattr(self, "s_" + k, None)
        if fn is not None:
            return fn(n, out, ind)
        # expression statement
        out.append(ind + self.expr_stmt(n))

    def expr_stmt(self, n):
        k = n["kind"]
        if k == "BinaryOperator" and n["opcode"] == "=":
            a, b = n["inner"]
            if b["kind"] == "BinaryOperator" and b["opcode"] == "=":
                # chained assignment a = b = c
                inner = self.expr_stmt(b)
                return inner + "; " + "%s = %s" % (self.lval(a), self.assign_rhs(a, b["inner"][0]))
            return "%s = %s" % (self.lval(a), self.assign_rhs(a, b))
        if k == "CompoundAssignOperator":
            op = n["opcode"]
            a, b = n["inner"]
            lt = odin_type(nct(a))
            comp = n.get("computeResultType", {}).get("qualType")
            lhs = self.lval(a)
            rhs = self.val(b)
            bop = op[:-1]
            if bop in ("<<", ">>") and b["kind"] != "IntegerLiteral":
                rhs = "uint(%s)" % rhs
            if comp and odin_type(ctype(comp)) != lt:
                ctp = odin_type(ctype(comp))
                return "%s = %s(%s(%s) %s %s)" % (lhs, lt, ctp, lhs, bop, rhs)
            return "%s %s= %s" % (lhs, bop, rhs)
        if k == "UnaryOperator" and n["opcode"] in ("++", "--"):
            return "%s %s= 1" % (self.lval(n["inner"][0]), "+" if n["opcode"] == "++" else "-")
        if k == "ParenExpr":
            return self.expr_stmt(n["inner"][0])
        if k in ("CStyleCastExpr", "ImplicitCastExpr") and qt(n) == "void":
            return self.expr_stmt(n["inner"][0])
        code, kind = self.expr(n)
        if k == "CallExpr":
            return code
        return "_ = %s" % code

    def block(self, n, out, ind):
        if n["kind"] == "CompoundStmt":
            for s in n.get("inner", []):
                self.stmt(s, out, ind)
        else:
            self.stmt(n, out, ind)

    def s_CompoundStmt(self, n, out, ind):
        out.append(ind + "{")
        self.block(n, out, ind + "\t")
        out.append(ind + "}")

    def s_NullStmt(self, n, out, ind):
        pass

    def s_DeclStmt(self, n, out, ind):
        for d in n["inner"]:
            if d["kind"] != "VarDecl":
                raise Fail("decl stmt %s" % d["kind"])
            name = d["name"]
            if d.get("storageClass") == "static":
                continue  # hoisted into Globals
            self.c.locals.add(name)
            ct = nct(d)
            ot = odin_type(ct)
            init = d.get("inner")
            if init:
                iv = init[0]
                if ct[0] == "array" and iv["kind"] == "StringLiteral":
                    out.append(ind + "%s: %s; cstr_init(%s[:], %s)" % (ident(name), ot, ident(name), self.strlit(iv["value"])))
                    continue
                if is_bool(ct):
                    v = self.cond(iv)
                elif iv["kind"] == "InitListExpr":
                    v = self.init_item(iv, ct)
                else:
                    v = self.val(iv)
                out.append(ind + "%s: %s = %s" % (ident(name), ot, v))
            else:
                out.append(ind + "%s: %s" % (ident(name), ot))

    def s_IfStmt(self, n, out, ind, prefix="if"):
        inner = n["inner"]
        cond = inner[0]
        then = inner[1]
        els = inner[2] if len(inner) > 2 else None
        out.append(ind + "%s %s {" % (prefix, self.cond(cond)))
        self.block(then, out, ind + "\t")
        if els is None:
            out.append(ind + "}")
        elif els["kind"] == "IfStmt":
            sub = []
            self.s_IfStmt(els, sub, ind, prefix="} else if")
            out.extend(sub)
        else:
            out.append(ind + "} else {")
            self.block(els, out, ind + "\t")
            out.append(ind + "}")

    def s_WhileStmt(self, n, out, ind):
        cond, body = n["inner"]
        out.append(ind + "for %s {" % self.cond(cond))
        self.block(body, out, ind + "\t")
        out.append(ind + "}")

    def s_DoStmt(self, n, out, ind):
        body, cond = n["inner"]
        self.c.tmp += 1
        v = "_do%d" % self.c.tmp
        out.append(ind + "for %s := true; %s || %s; %s = false {" % (v, v, self.paren_cond(cond), v))
        self.block(body, out, ind + "\t")
        out.append(ind + "}")

    def s_ForStmt(self, n, out, ind):
        inner = n["inner"]
        # clang: [init, condvar, cond, inc, body]
        init, _cv, cond, inc, body = inner
        parts = []
        pre = []
        if init and init.get("kind"):
            if init["kind"] == "DeclStmt":
                raise Fail("for decl")
            if init["kind"] == "BinaryOperator" and init["opcode"] == ",":
                for sub in self.comma_list(init):
                    pre.append(self.expr_stmt(sub))
                ini = ""
            else:
                ini = self.expr_stmt(init)
        else:
            ini = ""
        c = self.cond(cond) if cond and cond.get("kind") else ""
        if inc and inc.get("kind"):
            if inc["kind"] == "BinaryOperator" and inc["opcode"] == ",":
                raise Fail("for comma inc")
            st = self.expr_stmt(inc)
        else:
            st = ""
        for p in pre:
            out.append(ind + p)
        if not ini and not st:
            out.append(ind + ("for %s {" % c if c else "for {"))
        else:
            out.append(ind + "for %s; %s; %s {" % (ini, c, st))
        self.block(body, out, ind + "\t")
        out.append(ind + "}")

    def comma_list(self, n):
        if n["kind"] == "BinaryOperator" and n["opcode"] == ",":
            return self.comma_list(n["inner"][0]) + self.comma_list(n["inner"][1])
        return [n]

    def s_ReturnStmt(self, n, out, ind):
        inner = n.get("inner")
        if not inner:
            if self.c.ret is not None:
                out.append(ind + "return {}")
            else:
                out.append(ind + "return")
            return
        e = inner[0]
        if self.c.ret is None:
            out.append(ind + self.expr_stmt(e))
            out.append(ind + "return")
            return
        if is_bool(self.c.ret):
            out.append(ind + "return %s" % self.cond(e))
        else:
            code, kind = self.expr(e)
            if kind == "bool":
                code = "b2i(%s)" % code
            rt = odin_type(self.c.ret)
            try:
                et = odin_type(nct(e))
            except Fail:
                et = rt
            if et != rt and rt not in ("cstring", "rawptr") and not rt.startswith("^") and not rt.startswith("[^]"):
                code = "%s(%s)" % (rt, code)
            out.append(ind + "return %s" % code)

    def s_BreakStmt(self, n, out, ind):
        out.append(ind + "break")

    def s_ContinueStmt(self, n, out, ind):
        out.append(ind + "continue")

    def s_SwitchStmt(self, n, out, ind):
        inner = n["inner"]
        cond = inner[-2] if len(inner) > 2 else inner[0]
        body = inner[-1]
        out.append(ind + "switch %s {" % self.val(cond))
        groups = []  # list of (labels or None for default, [stmts])

        def add_label(node):
            # returns the statement following the label chain
            labels = []
            cur = node
            is_default = False
            while cur["kind"] in ("CaseStmt", "DefaultStmt"):
                if cur["kind"] == "CaseStmt":
                    labels.append(self.val(cur["inner"][0]))
                    cur = cur["inner"][-1]
                else:
                    is_default = True
                    cur = cur["inner"][0]
            return labels, is_default, cur

        stmts = body.get("inner", []) if body["kind"] == "CompoundStmt" else [body]
        for s in stmts:
            if s["kind"] in ("CaseStmt", "DefaultStmt"):
                labels, is_def, first = add_label(s)
                groups.append([labels, is_def, [first]])
            else:
                if not groups:
                    raise Fail("statement before first case")
                groups[-1][2].append(s)
        for gi, (labels, is_def, ss) in enumerate(groups):
            if is_def and labels:
                # default merged with cases: emit as default (labels dropped, same body)
                head = "case:"
            elif is_def:
                head = "case:"
            else:
                head = "case %s:" % ", ".join(labels)
            out.append(ind + head)
            # drop trailing break
            body_ss = list(ss)
            ends = False
            if body_ss and body_ss[-1]["kind"] == "BreakStmt":
                body_ss = body_ss[:-1]
                ends = True
            for s in body_ss:
                self.stmt(s, out, ind + "\t")
            if not ends and gi + 1 < len(groups):
                last = body_ss[-1] if body_ss else None
                if last is None or last["kind"] not in ("ReturnStmt", "ContinueStmt", "BreakStmt"):
                    out.append(ind + "\tfallthrough")
        out.append(ind + "}")

    def s_LabelStmt(self, n, out, ind):
        raise Fail("label")

    def s_GotoStmt(self, n, out, ind):
        raise Fail("goto")


OPNAMES = {"+": "add", "-": "sub", "*": "mul", "/": "div", "%": "mod", "&": "and", "|": "or",
           "^": "xor", "<<": "shl", ">>": "shr"}


# ---------------------------------------------------------------- driver

def prepare():
    if os.path.isdir(CSRC):
        shutil.rmtree(CSRC)
    shutil.copytree(SRC, CSRC)
    p = os.path.join(CSRC, "spacetrader.h")
    out = []
    for line in open(p, encoding="cp1252"):
        m = re.match(r"#define\s+(\w+)\s+(-?\d+)L?\s*(//.*|/\*.*)?$", line.rstrip("\n"))
        if m and m.group(1) not in ("appPrefVersionNum",):
            out.append("enum { %s = %s }; %s\n" % (m.group(1), m.group(2), m.group(3) or ""))
        else:
            out.append(line)
    open(p, "w", encoding="cp1252").write("".join(out))
    for f, old, new in PATCHES:
        fp = os.path.join(CSRC, f)
        s = open(fp, encoding="cp1252").read()
        if old not in s:
            raise Fail("patch not found in %s: %s" % (f, old))
        s = s.replace(old, new)
        open(fp, "w", encoding="cp1252").write(s)


def collect_typedefs(ast):
    for f, d in top_decls_with_file(ast):
        if d["kind"] == "TypedefDecl":
            name = d["name"]
            under = d["type"]["qualType"]
            TYPEDEF_DESUGAR.setdefault(name, under)


def collect_records(ast):
    """Find typedef'd anonymous structs from DataTypes.h."""
    pending = {}
    for f, d in top_decls_with_file(ast):
        if d["kind"] == "RecordDecl" and f and (f.endswith("DataTypes.h")):
            if d.get("completeDefinition"):
                fields = [(x["name"], x["type"]["qualType"]) for x in d.get("inner", []) if x["kind"] == "FieldDecl"]
                pending[d["id"]] = (d.get("name"), fields)
        if d["kind"] == "TypedefDecl" and f and f.endswith("DataTypes.h"):
            inner = d.get("inner", [{}])[0]
            owned = inner.get("ownedTagDecl") or inner.get("decl") or {}
            # ElaboratedType -> RecordType
            rid = None
            node = inner
            while node:
                if "ownedTagDecl" in node:
                    rid = node["ownedTagDecl"]["id"]
                    break
                if "decl" in node:
                    rid = node["decl"]["id"]
                    break
                node = (node.get("inner") or [None])[0]
            if rid in pending:
                RECORDS[d["name"]] = pending[rid][1]
                if pending[rid][0]:
                    RECORDS["struct " + pending[rid][0]] = pending[rid][1]
                    RECORDS[pending[rid][0]] = pending[rid][1]


def main():
    prepare()
    # SetField.c duplicates SetField from Field.c (an older copy in the package).
    cfiles = sorted(f for f in os.listdir(CSRC) if f.endswith(".c") and f != "SetField.c")
    asts = {}
    for f in cfiles:
        asts[f] = dump_ast(f)
    for f in cfiles:
        collect_typedefs(asts[f])
    collect_records(asts["Global.c"])
    # Odin-side named records from the Palm stub (not emitted)
    for nm in ("HighScoreType",):
        if "struct " + nm in RECORDS:
            pass

    # Pass 1: globals, functions, statics
    globals_def = {}     # name -> (ct, init node or None, const?)
    globals_order = []
    funcs = {}
    func_defs = []       # (file, node)
    static_map = {}
    static_defs = []     # (field, ct, init)
    for f in cfiles:
        main_file = f
        for loc, d in top_decls_with_file(asts[f]):
            if loc is None or not loc.endswith(main_file):
                continue
            k = d["kind"]
            if k == "VarDecl":
                if d.get("storageClass") == "extern":
                    continue
                name = d["name"]
                ct = nct(d)
                const = qt(d).startswith("const ") or ("const" in qt(d) and ct[0] == "array")
                init = d.get("inner", [None])[0] if d.get("inner") else None
                if name in globals_def:
                    if init is not None:
                        globals_def[name] = (ct, init, const, f)
                    continue
                globals_def[name] = (ct, init, const, f)
                globals_order.append(name)
            elif k == "FunctionDecl" and d.get("inner") and any(x["kind"] == "CompoundStmt" for x in d["inner"]):
                func_defs.append((f, d))
                # statics inside
                def find_statics(node, fname):
                    for ch in node.get("inner", []) or []:
                        if ch.get("kind") == "VarDecl" and ch.get("storageClass") == "static":
                            field = "%s__%s" % (fname, ch["name"])
                            static_map[(fname, ch["name"])] = field
                            static_defs.append((field, nct(ch), (ch.get("inner") or [None])[0]))
                        if isinstance(ch, dict):
                            find_statics(ch, fname)
                find_statics(d, d["name"])

    for _f, d in func_defs:
        try:
            FUNC_RETURNS[d["name"]] = ctype(d["type"]["qualType"].split("(")[0].strip())
        except Fail:
            pass
    mutable = [n for n in globals_order if not globals_def[n][2]]
    consts = [n for n in globals_order if globals_def[n][2]]
    ctx = Ctx(set(mutable), funcs, static_map)
    em = Emitter(ctx)

    files_out = {}

    # Records
    rec = ["// GENERATED by tools/transpile.py from reference/Src/DataTypes.h. Do not edit.",
           "package game", ""]
    done = set()
    for name, fields in RECORDS.items():
        if name.startswith("struct ") or name in done:
            continue
        if not re.match(r"^[A-Z][A-Za-z]*$", name):
            continue
        done.add(name)
        rec.append("%s :: struct {" % name)
        for fname, ftype in fields:
            rec.append("\t%s: %s," % (fname, odin_type(ctype(ftype))))
        rec.append("}")
        rec.append("")
    files_out["st_types.odin"] = rec

    # Numeric constants of spacetrader.h (turned into enums by prepare())
    cn = ["// GENERATED by tools/transpile.py from reference/Src/spacetrader.h. Do not edit.",
          "package game", ""]
    for line in open(os.path.join(CSRC, "spacetrader.h"), encoding="cp1252"):
        m = re.match(r"enum \{ (\w+) = (-?\d+) \};", line)
        if m:
            cn.append("%s :: %s" % (m.group(1), m.group(2)))
    files_out["st_constants.odin"] = cn

    # Globals struct and init
    gl = ["// GENERATED by tools/transpile.py from reference/Src (Global.c and file statics). Do not edit.",
          "package game", "", "Globals :: struct {"]
    for n in mutable:
        ct = globals_def[n][0]
        gl.append("\t%s: %s, // %s" % (n, odin_type(ct), globals_def[n][3]))
    for field, ct, init in static_defs:
        gl.append("\t%s: %s, // function static" % (field, odin_type(ct)))
    gl.append("}")
    gl.append("")
    gl.append("globals_init :: proc() {")
    gl.append("\tg^ = {}")
    for n in mutable:
        ct, init, _c, _f = globals_def[n]
        if init is None:
            continue
        if init["kind"] == "InitListExpr":
            gl.append("\tg.%s = %s" % (n, em.init_item(init, ct)))
        elif ct[0] == "array" and init["kind"] == "StringLiteral":
            gl.append("\tcstr_init(g.%s[:], %s)" % (n, em.strlit(init["value"])))
        elif is_bool(ct):
            gl.append("\tg.%s = %s" % (n, em.cond(init)))
        else:
            gl.append("\tg.%s = %s" % (n, em.val(init)))
    for field, ct, init in static_defs:
        if init is not None:
            if is_bool(ct):
                gl.append("\tg.%s = %s" % (field, em.cond(init)))
            else:
                gl.append("\tg.%s = %s" % (field, em.val(init)))
    gl.append("}")
    gl.append("")
    # const tables
    for n in consts:
        ct, init, _c, f = globals_def[n]
        ot = odin_type(ct)
        if init is None:
            gl.append("%s: %s" % (n, ot))
            continue
        if init["kind"] == "InitListExpr":
            items = []
            for x in init.get("inner", []):
                items.append("\t" + em.init_item(x, None) + ",")
            gl.append("%s := %s{" % (n, ot))
            gl.extend(items)
            gl.append("}")
        else:
            gl.append("%s := %s(%s)" % (n, ot, em.val(init)))
        gl.append("")
    files_out["st_globals.odin"] = gl

    # Functions
    failures = []
    per_file = {}
    for f, d in func_defs:
        name = d["name"]
        if name in OVERRIDES:
            continue
        lines = []
        try:
            lines = emit_function(em, ctx, d)
        except Fail as e:
            failures.append("%s:%s: %s" % (f, name, e))
            lines = ["// TRANSPILE FAILED: %s" % e, "%s :: proc() { unimplemented(\"%s\") }" % (ident(name), name), ""]
        per_file.setdefault(f, []).extend(lines)
    for f, lines in per_file.items():
        base = os.path.splitext(f)[0]
        fn = "st_%s.odin" % re.sub(r"(?<!^)(?=[A-Z])", "_", base).lower()
        files_out[fn] = ["// GENERATED by tools/transpile.py from reference/Src/%s" % f,
                         "// (Space Trader 1.2.2, Pieter Spronck, GPL). Do not edit; fix the generator", "// or add an override instead.",
                         "package game", ""] + lines

    for fn in list(os.listdir(OUT)) if os.path.isdir(OUT) else []:
        if fn.startswith("st_") and fn.endswith(".odin"):
            os.remove(os.path.join(OUT, fn))
    os.makedirs(OUT, exist_ok=True)
    for fn, lines in files_out.items():
        open(os.path.join(OUT, fn), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("transpiled %d functions into %d files; %d failures" % (len(func_defs), len(files_out), len(failures)))
    for x in failures:
        print("  FAIL", x)


def emit_function(em, ctx, d):
    name = d["name"]
    ftype = d["type"]["qualType"]
    ret_s = ftype.split("(")[0].strip()
    ret = ctype(ret_s)
    ctx.func = name
    ctx.ret = None if (ret[0] == "scalar" and ret[1] == "void") else ret
    ctx.locals = set()
    params = [x for x in d["inner"] if x["kind"] == "ParmVarDecl"]
    body = [x for x in d["inner"] if x["kind"] == "CompoundStmt"][0]
    ps = []
    mutated = set()
    find_param_mutations(body, set(p.get("name") for p in params), mutated)
    pre = []
    for p in params:
        pn = p.get("name", "_")
        pct = nct(p)
        ctx.locals.add(pn)
        if pn in mutated:
            ps.append("%s_in: %s" % (ident(pn), odin_type(pct)))
            pre.append("\t%s := %s_in" % (ident(pn), ident(pn)))
        else:
            ps.append("%s: %s" % (ident(pn), odin_type(pct)))
    rs = "" if ctx.ret is None else " -> %s" % odin_type(ctx.ret)
    out = ["%s :: proc(%s)%s {" % (ident(name), ", ".join(ps), rs)]
    out.extend(pre)
    em.block(body, out, "\t")
    if ctx.ret is not None and not ends_with_return(body):
        out.append("\treturn {}")
    out.append("}")
    out.append("")
    return out


def ends_with_return(body):
    inner = body.get("inner", [])
    if not inner:
        return False
    last = inner[-1]
    return last["kind"] == "ReturnStmt"


def find_param_mutations(node, names, out):
    if not isinstance(node, dict):
        return
    k = node.get("kind")
    if k in ("BinaryOperator", "CompoundAssignOperator") and (node.get("opcode") == "=" or k == "CompoundAssignOperator"):
        lhs = node["inner"][0]
        while lhs.get("kind") in ("ParenExpr", "ImplicitCastExpr"):
            lhs = lhs["inner"][0]
        if lhs.get("kind") == "DeclRefExpr" and lhs["referencedDecl"]["name"] in names and lhs["referencedDecl"]["kind"] == "ParmVarDecl":
            out.add(lhs["referencedDecl"]["name"])
    if k == "UnaryOperator" and node.get("opcode") in ("++", "--", "&"):
        lhs = node["inner"][0]
        while lhs.get("kind") in ("ParenExpr", "ImplicitCastExpr"):
            lhs = lhs["inner"][0]
        if lhs.get("kind") == "DeclRefExpr" and lhs["referencedDecl"]["name"] in names and lhs["referencedDecl"]["kind"] == "ParmVarDecl":
            out.add(lhs["referencedDecl"]["name"])
    for ch in node.get("inner", []) or []:
        find_param_mutations(ch, names, out)


if __name__ == "__main__":
    try:
        main()
    except Fail as e:
        print("transpile failed:", e, file=sys.stderr)
        sys.exit(1)
