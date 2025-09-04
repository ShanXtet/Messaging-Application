// Test Conversation Creation Script
// Run this with: node test-conversation.js

import mongoose from 'mongoose';
import 'dotenv/config';

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/MessageApp';

// Connect to MongoDB
await mongoose.connect(MONGODB_URI);
console.log('Connected to MongoDB');

// Define schemas
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

async function testConversationCreation() {
  try {
    console.log('\n=== TESTING CONVERSATION CREATION ===\n');

    // Get all users
    const users = await User.find({}).select('_id name email').lean();
    console.log(`Found ${users.length} users:`);
    users.forEach((user, index) => {
      console.log(`  ${index + 1}. ${user.name} (${user.email}) - ID: ${user._id}`);
    });

    if (users.length < 2) {
      console.log('❌ Need at least 2 users to create a conversation');
      return;
    }

    // Test conversation creation between first two users
    const user1 = users[0];
    const user2 = users[1];
    
    console.log(`\nTesting conversation between ${user1.name} and ${user2.name}...`);

    // Function to get or create conversation (same as in index.js)
    const getOrCreateConversation = async (participantIds) => {
      const sortedParticipants = participantIds.sort();
      
      // Try to find existing conversation
      let conversation = await Conversation.findOne({ 
        participants: { $all: sortedParticipants, $size: sortedParticipants.length }
      });
      
      if (!conversation) {
        try {
          conversation = await Conversation.create({
            participants: sortedParticipants,
            lastMessage: { text: '', from: null, timestamp: new Date() },
            unreadCount: new Map()
          });
          console.log('✅ Created new conversation:', conversation._id);
        } catch (error) {
          if (error.code === 11000) {
            // Duplicate key error - conversation already exists, try to find it again
            conversation = await Conversation.findOne({ 
              participants: { $all: sortedParticipants, $size: sortedParticipants.length }
            });
            if (!conversation) {
              throw new Error('Failed to create or find conversation');
            }
            console.log('✅ Found existing conversation after duplicate error:', conversation._id);
          } else {
            throw error;
          }
        }
      } else {
        console.log('✅ Found existing conversation:', conversation._id);
      }
      
      return conversation;
    };

    // Test the function
    const conversation = await getOrCreateConversation([user1._id, user2._id]);
    
    console.log('\nConversation details:');
    console.log(`  ID: ${conversation._id}`);
    console.log(`  Participants: ${conversation.participants}`);
    console.log(`  Created: ${conversation.createdAt}`);
    console.log(`  Last Message: "${conversation.lastMessage?.text || 'No message'}"`);

    // Test creating a message
    console.log('\nTesting message creation...');
    const testMessage = await Message.create({
      conversationId: conversation._id,
      from: user1._id,
      to: user2._id,
      text: 'Hello! This is a test message.',
      status: 'sent'
    });
    
    console.log('✅ Created test message:', testMessage._id);
    console.log(`  Text: "${testMessage.text}"`);
    console.log(`  From: ${testMessage.from}`);
    console.log(`  To: ${testMessage.to}`);
    console.log(`  Status: ${testMessage.status}`);

    // Update conversation last message
    await Conversation.findByIdAndUpdate(conversation._id, {
      lastMessage: {
        text: testMessage.text,
        from: testMessage.from,
        timestamp: testMessage.createdAt
      }
    });
    
    console.log('✅ Updated conversation last message');

    // Test file message
    console.log('\nTesting file message creation...');
    const fileMessage = await Message.create({
      conversationId: conversation._id,
      from: user2._id,
      to: user1._id,
      text: '',
      messageType: 'file',
      fileAttachment: {
        fileName: 'test-document.pdf',
        filePath: 'uploads/test-document.pdf',
        fileSize: 1024000,
        mimeType: 'application/pdf'
      },
      status: 'sent'
    });
    
    console.log('✅ Created file message:', fileMessage._id);
    console.log(`  File: ${fileMessage.fileAttachment.fileName}`);
    console.log(`  Size: ${fileMessage.fileAttachment.fileSize} bytes`);
    console.log(`  Type: ${fileMessage.messageType}`);

  } catch (error) {
    console.error('❌ Error testing conversation creation:', error);
  } finally {
    await mongoose.connection.close();
    console.log('\nDisconnected from MongoDB');
  }
}

// Run the test
testConversationCreation();
