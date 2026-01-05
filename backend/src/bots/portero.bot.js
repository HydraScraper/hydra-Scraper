/**
 * PorteroBot - Conversation Flow and State Machine Manager
 * 
 * This module provides a sophisticated bot framework for managing conversational flows,
 * state transitions, and dialogue context. It implements a state machine pattern to handle
 * complex multi-turn conversations with context preservation and flow control.
 * 
 * @author HydraScraper
 * @version 1.0.0
 */

class PorteroBot {
  /**
   * Initialize the PorteroBot with configuration and state management
   * 
   * @param {Object} config - Configuration object
   * @param {string} config.name - Bot name identifier
   * @param {string} config.version - Bot version
   * @param {Object} config.states - Available states definition
   * @param {string} config.initialState - Initial state on bot start
   * @param {number} config.sessionTimeout - Session timeout in milliseconds
   * @param {boolean} config.debug - Enable debug logging
   */
  constructor(config = {}) {
    this.name = config.name || 'PorteroBot';
    this.version = config.version || '1.0.0';
    this.initialState = config.initialState || 'idle';
    this.sessionTimeout = config.sessionTimeout || 3600000; // 1 hour default
    this.debug = config.debug || false;

    // State machine management
    this.states = new Map();
    this.currentState = this.initialState;
    this.previousState = null;
    
    // Conversation context and session management
    this.conversations = new Map(); // userId -> conversation context
    this.sessions = new Map(); // sessionId -> session data
    this.flowHistory = []; // Track conversation flow history
    
    // State definitions
    this.stateDefinitions = config.states || {};
    
    // Handlers for state transitions and events
    this.stateHandlers = new Map();
    this.eventHandlers = new Map();
    this.transitionCallbacks = new Map();
    
    // Timeout management
    this.sessionTimeouts = new Map();
    
    this._initializeStates();
  }

  /**
   * Initialize default states and their configurations
   * @private
   */
  _initializeStates() {
    const defaultStates = {
      idle: { type: 'initial', allowedTransitions: ['greeting', 'waiting'] },
      greeting: { type: 'interaction', allowedTransitions: ['processing', 'idle'] },
      processing: { type: 'working', allowedTransitions: ['responding', 'error', 'idle'] },
      responding: { type: 'interaction', allowedTransitions: ['awaiting_input', 'closing', 'idle'] },
      awaiting_input: { type: 'waiting', allowedTransitions: ['processing', 'closing', 'idle'] },
      error: { type: 'exception', allowedTransitions: ['recovering', 'idle'] },
      recovering: { type: 'recovery', allowedTransitions: ['idle', 'greeting'] },
      closing: { type: 'terminal', allowedTransitions: ['idle'] },
      waiting: { type: 'idle', allowedTransitions: ['greeting', 'closing', 'idle'] }
    };

    // Merge with provided state definitions
    const finalStates = { ...defaultStates, ...this.stateDefinitions };
    
    for (const [stateName, stateConfig] of Object.entries(finalStates)) {
      this.registerState(stateName, stateConfig);
    }
  }

  /**
   * Register a new state in the state machine
   * 
   * @param {string} stateName - Name of the state
   * @param {Object} config - State configuration
   * @returns {boolean} Success indicator
   */
  registerState(stateName, config = {}) {
    try {
      this.states.set(stateName, {
        name: stateName,
        type: config.type || 'standard',
        allowedTransitions: config.allowedTransitions || [],
        onEnter: config.onEnter || null,
        onExit: config.onExit || null,
        timeout: config.timeout || null,
        metadata: config.metadata || {}
      });
      
      this._log(`State registered: ${stateName}`);
      return true;
    } catch (error) {
      this._error(`Failed to register state ${stateName}:`, error);
      return false;
    }
  }

  /**
   * Register a handler for state entry
   * 
   * @param {string} stateName - Target state
   * @param {Function} handler - Handler function
   */
  onEnterState(stateName, handler) {
    if (typeof handler !== 'function') {
      throw new Error('State handler must be a function');
    }
    
    const state = this.states.get(stateName);
    if (!state) {
      throw new Error(`State '${stateName}' not found`);
    }
    
    state.onEnter = handler;
  }

  /**
   * Register a handler for state exit
   * 
   * @param {string} stateName - Target state
   * @param {Function} handler - Handler function
   */
  onExitState(stateName, handler) {
    if (typeof handler !== 'function') {
      throw new Error('State handler must be a function');
    }
    
    const state = this.states.get(stateName);
    if (!state) {
      throw new Error(`State '${stateName}' not found`);
    }
    
    state.onExit = handler;
  }

  /**
   * Register an event handler
   * 
   * @param {string} eventType - Type of event
   * @param {Function} handler - Handler function
   */
  on(eventType, handler) {
    if (typeof handler !== 'function') {
      throw new Error('Event handler must be a function');
    }
    
    if (!this.eventHandlers.has(eventType)) {
      this.eventHandlers.set(eventType, []);
    }
    
    this.eventHandlers.get(eventType).push(handler);
  }

  /**
   * Emit an event to all registered listeners
   * 
   * @param {string} eventType - Type of event
   * @param {Object} data - Event data
   */
  emit(eventType, data = {}) {
    if (this.eventHandlers.has(eventType)) {
      const handlers = this.eventHandlers.get(eventType);
      for (const handler of handlers) {
        try {
          handler(data);
        } catch (error) {
          this._error(`Error in event handler for ${eventType}:`, error);
        }
      }
    }
  }

  /**
   * Transition to a new state with validation and callbacks
   * 
   * @param {string} targetState - Target state name
   * @param {Object} context - Transition context data
   * @returns {Object} Transition result
   */
  async transitionTo(targetState, context = {}) {
    try {
      const sourceState = this.currentState;
      const state = this.states.get(sourceState);

      // Validate transition is allowed
      if (!state.allowedTransitions.includes(targetState)) {
        this._error(`Invalid transition: ${sourceState} -> ${targetState}`);
        return {
          success: false,
          error: `Transition not allowed from '${sourceState}' to '${targetState}'`,
          sourceState,
          targetState
        };
      }

      // Check if target state exists
      if (!this.states.has(targetState)) {
        this._error(`Target state '${targetState}' does not exist`);
        return {
          success: false,
          error: `Target state '${targetState}' not found`,
          sourceState,
          targetState
        };
      }

      // Execute exit handler for current state
      const currentState = this.states.get(sourceState);
      if (currentState.onExit) {
        await this._executeHandler(currentState.onExit, { sourceState, targetState, ...context });
      }

      // Emit transition event
      this.emit('state_transition', {
        from: sourceState,
        to: targetState,
        timestamp: new Date(),
        context
      });

      // Update state
      this.previousState = sourceState;
      this.currentState = targetState;

      // Record in flow history
      this.flowHistory.push({
        from: sourceState,
        to: targetState,
        timestamp: new Date(),
        context
      });

      // Execute enter handler for new state
      const newState = this.states.get(targetState);
      if (newState.onEnter) {
        await this._executeHandler(newState.onEnter, { sourceState, targetState, ...context });
      }

      // Execute transition callbacks
      this._executeTransitionCallbacks(sourceState, targetState, context);

      this._log(`Transitioned: ${sourceState} -> ${targetState}`);

      return {
        success: true,
        sourceState,
        targetState,
        timestamp: new Date()
      };

    } catch (error) {
      this._error(`Error during state transition to ${targetState}:`, error);
      return {
        success: false,
        error: error.message,
        targetState
      };
    }
  }

  /**
   * Create or retrieve conversation context for a user
   * 
   * @param {string} userId - Unique user identifier
   * @returns {Object} Conversation context
   */
  getOrCreateConversation(userId) {
    if (!this.conversations.has(userId)) {
      this.conversations.set(userId, {
        userId,
        startTime: new Date(),
        lastMessageTime: new Date(),
        messageCount: 0,
        context: {},
        messages: [],
        state: this.initialState,
        sessionId: this._generateSessionId()
      });
    }

    // Update last message time
    const conversation = this.conversations.get(userId);
    conversation.lastMessageTime = new Date();
    
    return conversation;
  }

  /**
   * Add a message to conversation history
   * 
   * @param {string} userId - User ID
   * @param {string} role - Message sender role ('user', 'bot', 'system')
   * @param {string} content - Message content
   * @param {Object} metadata - Additional metadata
   */
  addMessage(userId, role, content, metadata = {}) {
    const conversation = this.getOrCreateConversation(userId);
    
    conversation.messages.push({
      role,
      content,
      timestamp: new Date(),
      metadata
    });

    conversation.messageCount++;
    
    this.emit('message_added', {
      userId,
      role,
      content,
      timestamp: new Date()
    });

    return conversation.messages.length - 1; // Return message index
  }

  /**
   * Get conversation context
   * 
   * @param {string} userId - User ID
   * @returns {Object|null} Conversation context or null
   */
  getConversation(userId) {
    return this.conversations.get(userId) || null;
  }

  /**
   * Update conversation context data
   * 
   * @param {string} userId - User ID
   * @param {Object} contextData - Data to merge into context
   */
  updateConversationContext(userId, contextData = {}) {
    const conversation = this.getOrCreateConversation(userId);
    conversation.context = { ...conversation.context, ...contextData };
    
    this.emit('context_updated', {
      userId,
      context: conversation.context,
      timestamp: new Date()
    });
  }

  /**
   * Clear conversation for a user
   * 
   * @param {string} userId - User ID
   * @returns {boolean} Success indicator
   */
  clearConversation(userId) {
    return this.conversations.delete(userId);
  }

  /**
   * Get flow history
   * 
   * @param {number} limit - Maximum number of entries to return
   * @returns {Array} Flow history
   */
  getFlowHistory(limit = 50) {
    return this.flowHistory.slice(-limit);
  }

  /**
   * Reset the state machine to initial state
   * 
   * @returns {Promise<Object>} Reset result
   */
  async reset() {
    try {
      const result = await this.transitionTo(this.initialState, { reason: 'reset' });
      this.conversations.clear();
      this.flowHistory = [];
      this._log('PorteroBot reset to initial state');
      return result;
    } catch (error) {
      this._error('Error during reset:', error);
      throw error;
    }
  }

  /**
   * Get current state information
   * 
   * @returns {Object} Current state details
   */
  getCurrentStateInfo() {
    const state = this.states.get(this.currentState);
    return {
      name: this.currentState,
      ...state,
      timestamp: new Date(),
      previousState: this.previousState,
      conversationCount: this.conversations.size
    };
  }

  /**
   * Execute a handler function with error handling
   * @private
   */
  async _executeHandler(handler, context) {
    try {
      if (handler instanceof Promise || handler.constructor.name === 'AsyncFunction') {
        await handler(context);
      } else {
        handler(context);
      }
    } catch (error) {
      this._error('Error executing handler:', error);
      throw error;
    }
  }

  /**
   * Execute transition callbacks
   * @private
   */
  _executeTransitionCallbacks(fromState, toState, context) {
    const key = `${fromState}->${toState}`;
    if (this.transitionCallbacks.has(key)) {
      const callbacks = this.transitionCallbacks.get(key);
      for (const callback of callbacks) {
        try {
          callback(context);
        } catch (error) {
          this._error(`Error in transition callback (${key}):`, error);
        }
      }
    }
  }

  /**
   * Generate a unique session ID
   * @private
   */
  _generateSessionId() {
    return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Internal logging method
   * @private
   */
  _log(message) {
    if (this.debug) {
      console.log(`[${this.name}] ${message}`);
    }
  }

  /**
   * Internal error logging method
   * @private
   */
  _error(message, error = null) {
    const errorMsg = error ? `${message} ${error.message}` : message;
    console.error(`[${this.name}] ERROR: ${errorMsg}`);
    
    this.emit('error', {
      message: errorMsg,
      error,
      timestamp: new Date()
    });
  }

  /**
   * Get bot statistics
   * 
   * @returns {Object} Bot statistics
   */
  getStatistics() {
    let totalMessages = 0;
    this.conversations.forEach(conv => {
      totalMessages += conv.messageCount;
    });

    return {
      name: this.name,
      version: this.version,
      currentState: this.currentState,
      totalStates: this.states.size,
      activeConversations: this.conversations.size,
      totalMessages,
      flowHistoryLength: this.flowHistory.length,
      uptime: new Date() // Bot initialization time would be tracked separately
    };
  }
}

// Export the PorteroBot class
module.exports = PorteroBot;
