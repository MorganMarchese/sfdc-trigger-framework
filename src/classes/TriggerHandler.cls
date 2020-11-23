public virtual class TriggerHandler {

  // static map of handlername, times run() was invoked
  private static Map<String, LoopCount> loopCountMap;
  // static Set of Strings to bypass full Trigger Handlers
  private static Set<String> bypassedHandlers;
  // Static Map of Handlername, List of Bypassed Contexts
  private static Map<String, List<String>> bypassedHandlerContexts;
  
  // Variables for Concurrent Operation
  private static final Integer MAX_CONCURRENT_OPERATIONS = 5;
  private static final Integer MAX_IMPLICIT_BYPASS_LEVELS = 2;

  // the current context of the trigger, overridable in tests
  @TestVisible
  private TriggerContext context;

  // the current context of the trigger, overridable in tests
  @TestVisible
  private Boolean isTriggerExecuting;

  // static initialization
  static {
    loopCountMap = new Map<String, LoopCount>();
    bypassedHandlers = new Set<String>();
    bypassedHandlerContexts = new Map<String, List<String>>();
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

    if(!validateRun()) {
      return;
    }

    addToLoopCount();

    // dispatch to the correct handler method
    switch on this.context {
      when BEFORE_INSERT {
        this.beforeInsert();
      }
      when BEFORE_UPDATE {
        this.beforeUpdate();
      }
      when BEFORE_DELETE {
        this.beforeDelete();
      }
      when AFTER_INSERT {
        this.afterInsert();
      }
      when AFTER_UPDATE {
        this.afterUpdate();
      }
      when AFTER_DELETE {
        this.afterDelete();
      }
      when AFTER_UNDELETE {
        this.afterUndelete();
      }
    }
  }

  // method to set maximum loop count
  public void setMaxLoopCount(Integer max) {
    String handlerName = getHandlerName();
    if(!TriggerHandler.loopCountMap.containsKey(handlerName)) {
      TriggerHandler.loopCountMap.put(handlerName, new LoopCount(max));
    } else {
      TriggerHandler.loopCountMap.get(handlerName).setMax(max);
    }
  }

  // method to reset the loop count
  public void clearMaxLoopCount() {
    this.setMaxLoopCount(-1);
  }
  
  public Integer getLoopCount() {
    String handlerName = getHandlerName();
    if(TriggerHandler.loopCountMap.containsKey(handlerName)){
      return TriggerHandler.loopCountMap.get(handlerName).getCount();
    }
    else{
      return null;
    }
  }

  /***************************************
   * public static methods
   ***************************************/

  // bypass specific trigger handlers
  public static void bypass(String handlerName) {
    TriggerHandler.bypassedHandlers.add(handlerName);
  }

  // clear trigger handler bypass
  public static void clearBypass(String handlerName) {
    TriggerHandler.bypassedHandlers.remove(handlerName);
  }

  // check if handler is currently bypassed
  public static Boolean isBypassed(String handlerName) {
    return TriggerHandler.bypassedHandlers.contains(handlerName);
  }
  
  // bypass specific trigger handler context
  public static void bypassContext(String handlerName, String ctx) {
    if(TriggerHandler.bypassedHandlerContexts.containsKey(handlerName)) {
      TriggerHandler.bypassedHandlerContexts.get(handlerName).add(ctx);
    }
    else {
      TriggerHandler.bypassedHandlerContexts.put(handlerName, new List<String>{ctx});
    }
  }
  
  // clear all context bypasses for specific trigger handler
  public static void clearContextBypass(String handlerName) {
    TriggerHandler.bypassedHandlerContexts.remove(handlerName);
  }
  
  public static Boolean isContextBypassed(String handlerName, String ctx) {
    return TriggerHandler.bypassedHandlerContexts.get(handlerName).contains(ctx);
  }

  // clear all bypasses, including context bypasses
  public static void clearAllBypasses() {
    TriggerHandler.bypassedHandlers.clear();
    TriggerHandler.bypassedHandlerContexts.clear();
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
        Integer max = TriggerHandler.loopCountMap.get(handlerName).max;
        throw new TriggerHandlerException('Maximum loop count of ' + String.valueOf(max) + ' reached in ' + handlerName);
      }
      if(this.ENABLE_IMPLICIT_BYPASS) {
        TriggerHandler.loopCountMap.get(handlerName).implicitBypassBeforeExceeded(handlerName);
      }
    }
    else {
      TriggerHandler.loopCountMap.put(handlerName, new LoopCount(this.COONCURRENT_OPERATIONS, this.ENABLE_IMPLICIT_BYPASS, this.IMPLICIT_BYPASS_LEVELS));
    }
  }

  // make sure this trigger should continue to run
  @TestVisible
  private Boolean validateRun() {
    String handlerName = getHandlerName();
    if(!this.isTriggerExecuting || this.context == null) {
      throw new TriggerHandlerException('Trigger handler called outside of Trigger execution');
    }
    if(TriggerHandler.loopCountMap.containsKey(handlerName)) {
      // validate implicit bypass values
      if(this.ENABLE_IMPLICIT_BYPASS) {
        TriggerHandler.loopCountMap.get(handlerName).implicitBypassBeforeExceed(handlerName);
      }
      if(TriggerHandler.loopCountMap.get(handlerName).exceeded()) {
        throw new TriggerHandlerException('Maximum loop count of ' + TriggerHandler.loopCountMap.get(handler).max + ' reached in ' + handler);
      }
    }
    if(TriggerHandler.bypassedHandlers.contains(handlerName)) {
      return false;
    }
    if(TriggerHandler.bypassedHandlerContexts.containsKey(handlerName)) {
      if(TriggerHandler.bypassedContextForHandlers.get(handler).contains(this.context.name())) {
        return false;
      }
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
    private Integer enableImplicitBypass;

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
      return this.max >= 0 && this.count > this.max;
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
