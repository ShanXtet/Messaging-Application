// MongoDB Data Checker Script
// Run this with: node check-mongodb.js

import mongoose from 'mongoose';
import 'dotenv/config';

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/MessageApp';

// Connect to MongoDB
await mongoose.connect(MONGODB_URI);
console.log('Connected to MongoDB');

// Define schemas (same as in index.js)
const userSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  phone: { type: String, default: null },
  passwordHash: { type: String, required: true },
}, { timestamps: true });

const conversationSchema = new mongoose.Schema({
  participants: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true 
  }],
  lastMessage: {
    text: { type: String, trim: true },
    from: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    timestamp: { type: Date, default: Date.now }
  },
  unreadCount: {
    type: Map,
    of: Number,
    default: new Map()
  },
  isGroup: { type: Boolean, default: false },
  groupName: { type: String, trim: true },
  groupAdmin: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
}, { 
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

const messageSchema = new mongoose.Schema({
  conversationId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Conversation', 
    required: true, 
    index: true 
  },
  from: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  to: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  text: { type: String, trim: true, maxlength: 2000 },
  status: { type: String, enum: ['sent','delivered','read'], default: 'sent', index: true },
  seenAt: { type: Date, default: null },
  messageType: { type: String, enum: ['text', 'image', 'file'], default: 'text' },
  fileAttachment: {
    fileName: { type: String },
    filePath: { type: String },
    fileSize: { type: Number },
    mimeType: { type: String }
  }
}, { timestamps: true, toJSON: { virtuals: true }, toObject: { virtuals: true } });

const User = mongoose.model('User', userSchema);
const Conversation = mongoose.model('Conversation', conversationSchema);
const Message = mongoose.model('Message', messageSchema);

async function checkData() {
  try {
    console.log('\n=== MONGODB DATA CHECK ===\n');

    // Check Users
    console.log('1. USERS:');
    const users = await User.find({}).select('_id name email createdAt').lean();
    console.log(`Total users: ${users.length}`);
    users.forEach((user, index) => {
      console.log(`  ${index + 1}. ${user.name} (${user.email}) - ID: ${user._id}`);
    });

    // Check Conversations
    console.log('\n2. CONVERSATIONS:');
    const conversations = await Conversation.find({})
      .populate('participants', 'name email')
      .populate('lastMessage.from', 'name')
      .lean();
    console.log(`Total conversations: ${conversations.length}`);
    conversations.forEach((conv, index) => {
      console.log(`  ${index + 1}. Conversation ID: ${conv._id}`);
      console.log(`     Participants: ${conv.participants.map(p => p.name).join(', ')}`);
      console.log(`     Last Message: "${conv.lastMessage?.text || 'No message'}"`);
      console.log(`     Created: ${conv.createdAt}`);
      console.log('');
    });

    // Check Messages
    console.log('3. MESSAGES:');
    const messages = await Message.find({})
      .populate('from', 'name')
      .populate('to', 'name')
      .sort({ createdAt: -1 })
      .limit(10)
      .lean();
    console.log(`Total messages: ${await Message.countDocuments()}`);
    console.log('Recent messages:');
    messages.forEach((msg, index) => {
      console.log(`  ${index + 1}. From: ${msg.from?.name} → To: ${msg.to?.name}`);
      console.log(`     Text: "${msg.text}"`);
      console.log(`     Type: ${msg.messageType}`);
      if (msg.fileAttachment) {
        console.log(`     File: ${msg.fileAttachment.fileName} (${msg.fileAttachment.fileSize} bytes)`);
      }
      console.log(`     Status: ${msg.status} - ${msg.createdAt}`);
      console.log('');
    });

    // Check for potential conversation creation issues
    console.log('4. CONVERSATION CREATION ANALYSIS:');
    if (users.length >= 2) {
      console.log('Testing conversation creation between first two users...');
      const user1 = users[0];
      const user2 = users[1];
      
      // Check if conversation already exists
      const existingConv = await Conversation.findOne({
        participants: { $all: [user1._id, user2._id], $size: 2 }
      });
      
      if (existingConv) {
        console.log(`✅ Conversation already exists: ${existingConv._id}`);
      } else {
        console.log('❌ No conversation found between these users');
        console.log('This might be why conversations are not being created.');
      }
    }

    // Check indexes
    console.log('\n5. DATABASE INDEXES:');
    const conversationIndexes = await Conversation.collection.getIndexes();
    console.log('Conversation indexes:');
    Object.keys(conversationIndexes).forEach(indexName => {
      console.log(`  - ${indexName}: ${JSON.stringify(conversationIndexes[indexName])}`);
    });

  } catch (error) {
    console.error('Error checking data:', error);
  } finally {
    await mongoose.connection.close();
    console.log('\nDisconnected from MongoDB');
  }
}

// Run the check
checkData();
