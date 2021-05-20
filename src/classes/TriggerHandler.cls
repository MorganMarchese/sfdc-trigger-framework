/**********************************************************************************************************
Name       :  TriggerHandler
Description:  
Date               Version     Author             Summary of Changes 
*****            **********   **********         ********************

**********************************************************************************************************/
public virtual class TriggerHandler { 
    
    // static map of handlername, times run() was invokzed
    private static Map<String, LoopCount> loopCountMap;
    // set to bypass sepcific handlers
    private static Set<String> bypassedHandlers;
    // map to bypass specific contexts
    private static Map<String, List<String>> bypassedContextForHandlers;
    
    // add concurrent ops allowed
    private final static Integer MAX_CONCURRENT_OPERATIONS = 5; 
    private final static Integer MAX_IMPLICIT_BYPASS_LEVELS = 2; 

    // the current context of the trigger, overridable in tests
    @TestVisible
    private TriggerContext context;

    // the current context of the trigger, overridable in tests
    @TestVisible
    private Boolean isTriggerExecuting;

    // public static variable which can be used to throw exception on stack depth exceeded or perform and implicit bypass
    public Boolean ENABLE_IMPLICIT_BYPASS = false; // instantiate in constructor of object handler
    public Integer IMPLICIT_BYPASS_LEVELS = MAX_IMPLICIT_BYPASS_LEVELS; // instantiate in constructor of object handler
    public Integer CONCURRENT_OPERATIONS = MAX_CONCURRENT_OPERATIONS; // instantiate in constructor of object handler

    // static initialization
    static {
        loopCountMap = new Map<String, LoopCount>();
        bypassedHandlers = new Set<String>();
        bypassedContextForHandlers = new Map<String, List<String>>();
    }

    // constructor
    public TriggerHandler() {
        this.setTriggerContext();
    }

    /***************************************
     * public instance methods
     ***************************************/

    // main method that will be called during execution
    public void run() {
        if(!validateRun()) return;
        
        addToLoopCount();

        // dispatch to the correct handler method
        if(this.context == TriggerContext.BEFORE_INSERT) {
            this.beforeInsert();
        } else if(this.context == TriggerContext.BEFORE_UPDATE) {
            this.beforeUpdate();
        } else if(this.context == TriggerContext.BEFORE_DELETE) {
            this.beforeDelete();
        } else if(this.context == TriggerContext.AFTER_INSERT) {
            this.afterInsert();
        } else if(this.context == TriggerContext.AFTER_UPDATE) {
            this.afterUpdate();
        } else if(this.context == TriggerContext.AFTER_DELETE) {
            this.afterDelete();
        } else if(this.context == TriggerContext.AFTER_UNDELETE) {
            this.afterUndelete();
        }

    }
    
    // method to set a max in the loopcount
    public void setMaxLoopCount(Integer max) {
        String handlerName = getHandlerName();
        if(!TriggerHandler.loopCountMap.containsKey(handlerName)) {
            TriggerHandler.loopCountMap.put(handlerName, new LoopCount(max));
        } else {
            TriggerHandler.loopCountMap.get(handlerName).setMax(max);
        }
    }
    
    // method to reset the transaction count
    public void resetTransactionCount() {
        this.setMaxLoopCount(-1);
    }
    
    // get the number of run() already called
    public Integer getTransactionCount() {
        String handlerName = getHandlerName();
        if (TriggerHandler.loopCountMap.containsKey(handlerName)){
            return TriggerHandler.loopCountMap.get(handlerName).getCount();
        }
        else{
            return null;
        }
    }
    
    /***************************************
     * public static methods
     ***************************************/
    
    // bypass specific handlers
    public static void bypass(String handlerName) {
        TriggerHandler.bypassedHandlers.add(handlerName);
    }
    
    // bypass specific context
    public static void bypassContext(String handlerName, String ctx) {
        if(TriggerHandler.bypassedContextForHandlers.containsKey(handlerName)) {
            TriggerHandler.bypassedContextForHandlers.get(handlerName).add(ctx);
        }else {
            TriggerHandler.bypassedContextForHandlers.put(handlerName, new List<String>{ctx});
        }
    }
    
    // clear all context bypass for specific bypass
    public static void clearContextBypass(String handlerName) {
        TriggerHandler.bypassedContextForHandlers.remove(handlerName);
    }
    
    // check if handler is bypassed
    public static Boolean isHandlerBypassed(String handlerName) {
        return TriggerHandler.bypassedHandlers.contains(handlerName);
    }
    
    // check if specific context is bypassed
    public static Boolean isContextBypassed(String handlerName, String ctx) {
        return TriggerHandler.bypassedContextForHandlers.get(handlerName).contains(ctx);
    }
    
    // clear all bypasses
    public static void clearAllBypasses() {
        TriggerHandler.bypassedHandlers.clear();
        TriggerHandler.bypassedContextForHandlers.clear();
    }

    /***************************************
     * private instancemethods
     ***************************************/

    @TestVisible
    private void setTriggerContext() {
        this.setTriggerContext(null, false);
    }

    @TestVisible
    private void setTriggerContext(String ctx, Boolean testMode) {
        if(!Trigger.isExecuting && !testMode) {
            this.isTriggerExecuting = false;
            return;
        } else {
            this.isTriggerExecuting = true;
        }

        if((Trigger.isExecuting && Trigger.isBefore && Trigger.isInsert) ||
                (ctx != null && ctx == 'before insert')) {
            this.context = TriggerContext.BEFORE_INSERT;
        } else if((Trigger.isExecuting && Trigger.isBefore && Trigger.isUpdate) ||
                (ctx != null && ctx == 'before update')){
            this.context = TriggerContext.BEFORE_UPDATE;
        } else if((Trigger.isExecuting && Trigger.isBefore && Trigger.isDelete) ||
                (ctx != null && ctx == 'before delete')) {
            this.context = TriggerContext.BEFORE_DELETE;
        } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isInsert) ||
                (ctx != null && ctx == 'after insert')) {
            this.context = TriggerContext.AFTER_INSERT;
        } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isUpdate) ||
                (ctx != null && ctx == 'after update')) {
            this.context = TriggerContext.AFTER_UPDATE;
        } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isDelete) ||
                (ctx != null && ctx == 'after delete')) {
            this.context = TriggerContext.AFTER_DELETE;
        } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isUndelete) ||
                (ctx != null && ctx == 'after undelete')) {
            this.context = TriggerContext.AFTER_UNDELETE;
        }
    }

    // increment the loop count
    @TestVisible
    private void addToLoopCount() {
        String handlerName = getHandlerName();
        if(TriggerHandler.loopCountMap.containsKey(handlerName)) {
            Boolean exceeded = TriggerHandler.loopCountMap.get(handlerName).increment();
            if(exceeded) {
                throw new TriggerHandlerException('Maximum loop count of ' + TriggerHandler.loopCountMap.get(handlerName).max + ' reached in ' + handlerName);
            }
            if(this.ENABLE_IMPLICIT_BYPASS) {
                TriggerHandler.loopCountMap.get(handlerName).implicitBypassBeforeExceed(handlerName);
            }
        }
        else {
            TriggerHandler.loopCountMap.put(handlerName, new LoopCount(this.CONCURRENT_OPERATIONS , this.ENABLE_IMPLICIT_BYPASS , this.IMPLICIT_BYPASS_LEVELS));
        }
    }

    // make sure this trigger should continue to run
    @TestVisible
    private Boolean validateRun() {
        String handler = getHandlerName(); 
        // validate number of run()
        if(TriggerHandler.loopCountMap.containsKey(handler)) { 
            // validate implicit bypass
            if(this.ENABLE_IMPLICIT_BYPASS) {
                TriggerHandler.loopCountMap.get(handler).implicitBypassBeforeExceed(handler);
            }
            // throw exception on exceeding max concurrent operations
            if(TriggerHandler.loopCountMap.get(handler).exceeded()) {
                throw new TriggerHandlerException('Maximum loop count of ' + TriggerHandler.loopCountMap.get(handler).max + ' reached in ' + handler);
            }
        }
        if(!this.isTriggerExecuting || this.context == null) {
            throw new TriggerHandlerException('Trigger handler called outside of Trigger execution');
        }
        // validate handler
        if(TriggerHandler.bypassedHandlers.contains(handler)) { 
            return false;
        }
        // validate context for specific handler
        if(TriggerHandler.bypassedContextForHandlers.containsKey(handler) && TriggerHandler.bypassedContextForHandlers.get(handler).contains(this.context.name())) { 
            return false;
        }
        return true;
    }

    @TestVisible
    private String getHandlerName() {
        return String.valueOf(this).substring(0,String.valueOf(this).indexOf(':'));
    }

    /***************************************
     * context methods
     ***************************************/

    // context-specific methods for override
    @TestVisible
    protected virtual void beforeInsert(){}
    @TestVisible
    protected virtual void beforeUpdate(){}
    @TestVisible
    protected virtual void beforeDelete(){}
    @TestVisible
    protected virtual void afterInsert(){}
    @TestVisible
    protected virtual void afterUpdate(){}
    @TestVisible
    protected virtual void afterDelete(){}
    @TestVisible
    protected virtual void afterUndelete(){}

    /***************************************
     * inner classes
     ***************************************/

    // inner class for managing the loop count per handler
    @TestVisible
    private class LoopCount {
        private Integer max;
        private Integer count;
        private Integer implicitBypassCount;
        private Boolean enableImplicitBypass;

        public LoopCount() {
            this.max = TriggerHandler.MAX_CONCURRENT_OPERATIONS; 
            this.count = 0; 
            this.implicitBypassCount = TriggerHandler.MAX_IMPLICIT_BYPASS_LEVELS;
            this.enableImplicitBypass = false; 
        } 
        
        // overloaded constructor
        public LoopCount(Integer max) {
            this.max = max;
            this.count = 0;
            this.implicitBypassCount = TriggerHandler.MAX_IMPLICIT_BYPASS_LEVELS; 
            this.enableImplicitBypass = false; 
        }
        
        // overloaded constructor
        public LoopCount(Integer max, Boolean enableImplicitBypass, Integer implicitBypassCount) {
            this.max = max; 
            this.count = 0; 
            this.implicitBypassCount = implicitBypassCount; 
            this.enableImplicitBypass = enableImplicitBypass; 
        } 

        public Boolean increment() {
            this.count++;
            return this.exceeded();
        }

        public Boolean exceeded() {
            if(this.max < 0) return false;
            if(this.count > this.max) {
                return true;
            }
            return false;
        }

        public Integer getMax() {
            return this.max;
        }

        public Integer getCount() {
            return this.count;
        }

        public void setMax(Integer max) {
            this.max = max;
        }
        
        // instead of throwing exception after defined run, the handler will be added to a bypass list
        public void implicitBypassBeforeExceed(String handlerName) {
            if(this.count > this.implicitBypassCount && this.enableImplicitBypass) {
                TriggerHandler.bypass(handlerName);
            }
        }
    }

    // possible trigger contexts
    @TestVisible
    private enum TriggerContext {
        BEFORE_INSERT, BEFORE_UPDATE, BEFORE_DELETE,
        AFTER_INSERT, AFTER_UPDATE, AFTER_DELETE,
        AFTER_UNDELETE
    }

    // exception class
    public class TriggerHandlerException extends Exception {}

}
