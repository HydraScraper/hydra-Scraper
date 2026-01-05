/**
 * ComandanteBot - Quick Command Handler
 * Handles user commands with aliases for various bot operations
 * Created: 2026-01-05 14:15:45 UTC
 */

class ComandanteBot {
  constructor(config = {}) {
    this.config = {
      prefix: config.prefix || '/',
      responseDelay: config.responseDelay || 1000,
      ...config
    };

    this.commands = this.initializeCommands();
    this.aliases = this.initializeAliases();
  }

  /**
   * Initialize all available commands
   */
  initializeCommands() {
    return {
      help: {
        name: 'help',
        description: 'Display help information and available commands',
        handler: this.handleHelp.bind(this),
        aliases: ['h', 'info', '?', 'assist']
      },
      catalog: {
        name: 'catalog',
        description: 'Browse the product/service catalog',
        handler: this.handleCatalog.bind(this),
        aliases: ['c', 'products', 'services', 'menu', 'list']
      },
      booking: {
        name: 'booking',
        description: 'Make or manage a booking',
        handler: this.handleBooking.bind(this),
        aliases: ['b', 'book', 'reserve', 'schedule', 'appointment']
      },
      status: {
        name: 'status',
        description: 'Check booking or order status',
        handler: this.handleStatus.bind(this),
        aliases: ['s', 'check', 'track', 'progress', 'update']
      },
      pricing: {
        name: 'pricing',
        description: 'View pricing information',
        handler: this.handlePricing.bind(this),
        aliases: ['p', 'price', 'cost', 'rates', 'fees']
      },
      hours: {
        name: 'hours',
        description: 'Display operating hours',
        handler: this.handleHours.bind(this),
        aliases: ['h', 'time', 'open', 'schedule', 'availability']
      },
      location: {
        name: 'location',
        description: 'Get location information',
        handler: this.handleLocation.bind(this),
        aliases: ['l', 'address', 'where', 'map', 'directions']
      },
      contact: {
        name: 'contact',
        description: 'Get contact information',
        handler: this.handleContact.bind(this),
        aliases: ['ct', 'email', 'phone', 'support', 'reach']
      },
      faq: {
        name: 'faq',
        description: 'Frequently asked questions',
        handler: this.handleFaq.bind(this),
        aliases: ['f', 'question', 'questions', 'qa', 'common']
      },
      support: {
        name: 'support',
        description: 'Get customer support assistance',
        handler: this.handleSupport.bind(this),
        aliases: ['sup', 'help', 'assist', 'agent', 'ticket']
      },
      cancel: {
        name: 'cancel',
        description: 'Cancel a booking or order',
        handler: this.handleCancel.bind(this),
        aliases: ['x', 'terminate', 'abort', 'stop', 'delete']
      },
      refund: {
        name: 'refund',
        description: 'Request a refund',
        handler: this.handleRefund.bind(this),
        aliases: ['r', 'money-back', 'reimbursement', 'return', 'claim']
      }
    };
  }

  /**
   * Initialize command aliases mapping
   */
  initializeAliases() {
    const aliases = {};

    Object.values(this.commands).forEach(command => {
      // Map primary command name
      aliases[command.name] = command.name;

      // Map all aliases to command name
      if (command.aliases && Array.isArray(command.aliases)) {
        command.aliases.forEach(alias => {
          aliases[alias] = command.name;
        });
      }
    });

    return aliases;
  }

  /**
   * Parse incoming command
   * @param {string} input - User input
   * @returns {Object} Parsed command object
   */
  parseCommand(input) {
    const trimmed = input.trim();
    const hasPrefix = trimmed.startsWith(this.config.prefix);
    const commandStr = hasPrefix ? trimmed.slice(1) : trimmed;
    const parts = commandStr.split(/\s+/);
    const commandAlias = parts[0].toLowerCase();
    const args = parts.slice(1);

    return {
      raw: input,
      hasPrefix,
      commandAlias,
      args,
      fullArgs: args.join(' ')
    };
  }

  /**
   * Execute a command
   * @param {string} input - User input
   * @returns {Promise<Object>} Command response
   */
  async execute(input) {
    try {
      const parsed = this.parseCommand(input);
      const commandName = this.aliases[parsed.commandAlias];

      if (!commandName) {
        return this.handleUnknownCommand(parsed.commandAlias);
      }

      const command = this.commands[commandName];
      const response = await command.handler(parsed.args, parsed.fullArgs);

      return {
        success: true,
        command: commandName,
        timestamp: new Date().toISOString(),
        data: response
      };
    } catch (error) {
      return {
        success: false,
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }

  /**
   * Command Handlers
   */

  async handleHelp(args) {
    const commandList = Object.values(this.commands).map(cmd => ({
      command: `${this.config.prefix}${cmd.name}`,
      description: cmd.description,
      aliases: cmd.aliases.join(', ')
    }));

    return {
      title: '📚 Available Commands',
      commands: commandList,
      hint: `Use ${this.config.prefix}help [command] for detailed information`
    };
  }

  async handleCatalog(args) {
    return {
      title: '📦 Product/Service Catalog',
      message: 'Retrieving catalog items...',
      filters: ['category', 'price', 'rating'],
      action: 'browse'
    };
  }

  async handleBooking(args) {
    return {
      title: '📅 Booking System',
      message: 'Access booking management',
      options: ['new-booking', 'modify', 'view-bookings'],
      action: 'book'
    };
  }

  async handleStatus(args) {
    return {
      title: '✅ Status Check',
      message: 'Checking booking/order status...',
      action: 'status',
      details: args.join(' ') || 'latest booking'
    };
  }

  async handlePricing(args) {
    return {
      title: '💰 Pricing Information',
      message: 'Current pricing details',
      currency: 'USD',
      action: 'pricing',
      showDetails: args.length > 0
    };
  }

  async handleHours(args) {
    return {
      title: '🕐 Operating Hours',
      message: 'Our business hours',
      timezone: 'UTC',
      action: 'hours'
    };
  }

  async handleLocation(args) {
    return {
      title: '📍 Location Information',
      message: 'Find us here',
      action: 'location',
      requestMap: args.includes('map')
    };
  }

  async handleContact(args) {
    return {
      title: '📞 Contact Information',
      message: 'How to reach us',
      channels: ['email', 'phone', 'chat', 'social-media'],
      action: 'contact'
    };
  }

  async handleFaq(args) {
    return {
      title: '❓ Frequently Asked Questions',
      message: 'Browse common questions and answers',
      action: 'faq',
      searchTerm: args.join(' ') || null
    };
  }

  async handleSupport(args) {
    return {
      title: '🆘 Customer Support',
      message: 'Connect with our support team',
      options: ['live-chat', 'ticket', 'callback'],
      action: 'support',
      priority: args.includes('urgent') ? 'high' : 'normal'
    };
  }

  async handleCancel(args) {
    return {
      title: '❌ Cancel Booking/Order',
      message: 'Initiate cancellation process',
      action: 'cancel',
      target: args.join(' ') || 'latest',
      requireConfirmation: true
    };
  }

  async handleRefund(args) {
    return {
      title: '💵 Refund Request',
      message: 'Process refund request',
      action: 'refund',
      target: args.join(' ') || 'latest',
      requireConfirmation: true
    };
  }

  async handleUnknownCommand(command) {
    return {
      success: false,
      error: `Unknown command: ${command}`,
      suggestion: `Type ${this.config.prefix}help to see available commands`
    };
  }

  /**
   * Get all available commands
   */
  getCommands() {
    return Object.values(this.commands).map(cmd => ({
      name: cmd.name,
      description: cmd.description,
      aliases: cmd.aliases
    }));
  }

  /**
   * Get command by name or alias
   */
  getCommand(nameOrAlias) {
    const commandName = this.aliases[nameOrAlias.toLowerCase()];
    return commandName ? this.commands[commandName] : null;
  }

  /**
   * Check if command exists
   */
  hasCommand(nameOrAlias) {
    return nameOrAlias.toLowerCase() in this.aliases;
  }
}

/**
 * Export as CommonJS module
 */
module.exports = ComandanteBot;

/**
 * Example Usage:
 * 
 * const ComandanteBot = require('./comandante.bot');
 * const bot = new ComandanteBot({ prefix: '/' });
 * 
 * // Execute command
 * const result = await bot.execute('/help');
 * 
 * // Using aliases
 * const statusResult = await bot.execute('/s 12345');
 * 
 * // Get available commands
 * const commands = bot.getCommands();
 */
