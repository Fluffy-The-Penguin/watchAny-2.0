package com.googlecode.dex2jar.ir.ts;

import com.googlecode.dex2jar.ir.IrMethod;
import com.googlecode.dex2jar.ir.expr.Exprs;
import com.googlecode.dex2jar.ir.expr.InvokeExpr;
import com.googlecode.dex2jar.ir.expr.Local;
import com.googlecode.dex2jar.ir.expr.NewExpr;
import com.googlecode.dex2jar.ir.expr.Value;
import com.googlecode.dex2jar.ir.stmt.AssignStmt;
import com.googlecode.dex2jar.ir.stmt.Stmt;
import com.googlecode.dex2jar.ir.stmt.Stmts;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

public class NewTransformer implements Transformer {
    static final Vx IGNORED = new Vx(null, true);

    public static class TObject {
        public AssignStmt initStmt;
        public Stmt invokeStmt;
        public Local local;
        public boolean useBeforeInit = false;

        public TObject(Local local, AssignStmt initStmt) {
            this.local = local;
            this.initStmt = initStmt;
        }
    }

    public static class Vx {
        public boolean ignored;
        public TObject obj;

        public Vx(TObject obj, boolean ignored) {
            this.obj = obj;
            this.ignored = ignored;
        }
    }

    @Override
    public void transform(IrMethod irMethod) {
        replaceX(irMethod);
        replaceAST(irMethod);
    }

    void replaceX(IrMethod irMethod) {
        Map<Local, TObject> map = new HashMap<>();
        for (Stmt stmt : irMethod.stmts) {
            if (stmt.st == Stmt.ST.ASSIGN && stmt.getOp1().vt == Value.VT.LOCAL && stmt.getOp2().vt == Value.VT.NEW) {
                Local local = (Local) stmt.getOp1();
                map.put(local, new TObject(local, (AssignStmt) stmt));
            }
        }
        if (!map.isEmpty()) {
            int reIndexLocal = Cfg.reIndexLocal(irMethod);
            makeSureUsedBeforeConstructor(irMethod, map, reIndexLocal);
            if (!map.isEmpty()) {
                replace0(irMethod, map, reIndexLocal);
            }
            for (Stmt stmt : irMethod.stmts) {
                stmt.frame = null;
            }
        }
    }

    void replaceAST(IrMethod irMethod) {
        Iterator<Stmt> iterator = irMethod.stmts.iterator();
        while (iterator.hasNext()) {
            Stmt stmt = iterator.next();
            InvokeExpr findInvokeExpr = findInvokeExpr(stmt);
            if (findInvokeExpr != null && "<init>".equals(findInvokeExpr.getName())) {
                Value[] ops = findInvokeExpr.getOps();
                if (ops.length > 0 && ops[0].vt == Value.VT.NEW) {
                    NewExpr newExpr = (NewExpr) ops[0];
                    if (newExpr != null) {
                        Value[] args = Arrays.copyOfRange(ops, 1, ops.length);
                        InvokeExpr nInvokeNew = Exprs.nInvokeNew(args, findInvokeExpr.getArgs(), findInvokeExpr.getOwner());
                        irMethod.stmts.insertBefore(stmt, Stmts.nVoidInvoke(nInvokeNew));
                        iterator.remove();
                    }
                }
            }
        }
    }

    void replace0(IrMethod irMethod, Map<Local, TObject> map, int numLocals) {
        Set<Local> set = new HashSet<>();
        Local[] localsArr = new Local[numLocals];
        for (Local local : irMethod.locals) {
            localsArr[local.lsIndex] = local;
        }

        for (TObject tObject : map.values()) {
            if (tObject.invokeStmt == null || tObject.invokeStmt.frame == null) {
                continue;
            }
            Vx[] vxArr = (Vx[]) tObject.invokeStmt.frame;
            for (int i = 0; i < vxArr.length; i++) {
                Vx vx = vxArr[i];
                if (vx != null && vx.obj == tObject && !vx.ignored) {
                    Local local = localsArr[i];
                    set.add(local);
                    irMethod.stmts.insertBefore(tObject.initStmt, Stmts.nAssign(local, tObject.initStmt.getOp2()));
                    irMethod.stmts.insertAfter(tObject.initStmt, Stmts.nAssign(tObject.local, local));
                }
            }
            InvokeExpr findInvokeExpr = findInvokeExpr(tObject.invokeStmt);
            if (findInvokeExpr != null) {
                Value[] ops = findInvokeExpr.getOps();
                Value[] args = Arrays.copyOfRange(ops, 1, ops.length);
                InvokeExpr nInvokeNew = Exprs.nInvokeNew(args, findInvokeExpr.getArgs(), findInvokeExpr.getOwner());
                irMethod.stmts.replace(tObject.invokeStmt, Stmts.nAssign(tObject.local, nInvokeNew));
            }
        }
    }

    void makeSureUsedBeforeConstructor(IrMethod irMethod, Map<Local, TObject> map, int numLocals) {
        Cfg.createCFG(irMethod);
        Cfg.dfs(irMethod.stmts, new NewTransformer$1(this, numLocals, map));
        Iterator<Map.Entry<Local, TObject>> it = map.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<Local, TObject> entry = it.next();
            TObject tObject = entry.getValue();
            if (tObject.invokeStmt == null) {
                // Try to locate closest constructor call for this object type in irMethod.stmts
                String targetType = ((NewExpr) tObject.initStmt.getOp2()).type;
                for (Stmt stmt : irMethod.stmts) {
                    InvokeExpr inv = findInvokeExpr(stmt);
                    if (inv != null && "<init>".equals(inv.getName()) && inv.getOwner().equals(targetType)) {
                        tObject.invokeStmt = stmt;
                        tObject.useBeforeInit = false;
                        break;
                    }
                }
            }
            if (tObject.invokeStmt == null) {
                it.remove();
            }
        }
    }

    InvokeExpr findInvokeExpr(Stmt stmt) {
        if (stmt.st == Stmt.ST.ASSIGN && stmt.getOp2().vt == Value.VT.INVOKE_SPECIAL) {
            return (InvokeExpr) stmt.getOp2();
        }
        if (stmt.st == Stmt.ST.VOID_INVOKE && (stmt.getOp() instanceof InvokeExpr)) {
            return (InvokeExpr) stmt.getOp();
        }
        return null;
    }
}
