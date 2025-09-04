// server/src/index.js
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import validator from 'validator';
import jwt from 'jsonwebtoken';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const app = express();
app.use(helmet());
app.use(cors({ origin: true }));
app.use(express.json({ limit: '1mb' }));

// File upload configuration
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    // Allow all file types for now
    cb(null, true);
  }
});

// Serve uploaded files
app.use('/uploads', express.static('uploads'));

const PORT = process.env.PORT || 4000;
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/MessageApp';
const JWT_SECRET = process.env.JWT_SECRET || 'dev_change_me';

// --- DB ---
mongoose.set('strictQuery', true);
mongoose.set('debug', true); // debug logs
await mongoose.connect(MONGODB_URI);
console.log('[mongo] connected');

// Drop the problematic unique index if it exists
try {
  await mongoose.connection.db.collection('conversations').dropIndex('participants_1');
  console.log('[mongo] Dropped problematic unique index on participants');
} catch (error) {
  // Index might not exist, that's okay
  console.log('[mongo] Index drop result:', error.message);
}

// --- Models ---
const userSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  phone: { type: String, default: null },
  passwordHash: { type: String, required: true },
}, { timestamps: true });
userSchema.index({ email: 1 }, { unique: true });
const User = mongoose.model('User', userSchema);

// Conversation/Thread Schema
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

// Index for performance
conversationSchema.index({ 'lastMessage.timestamp': -1 });
conversationSchema.index({ participants: 1 });
// Compound index for better conversation lookup
conversationSchema.index({ participants: 1, isGroup: 1 });

const Conversation = mongoose.model('Conversation', conversationSchema);

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
messageSchema.index({ conversationId: 1, createdAt: -1 });
messageSchema.index({ from: 1, to: 1, createdAt: -1 });
messageSchema.virtual('sender').get(function(){ return this.from; }).set(function(v){ this.from = v; });
messageSchema.virtual('receiver').get(function(){ return this.to; }).set(function(v){ this.to = v; });
const Message = mongoose.model('Message', messageSchema);

// --- Conversation helpers ---
const getOrCreateConversation = async (participantIds) => {
  // Sort participant IDs for consistent lookup
  const sortedParticipants = participantIds.sort();
  console.log('[conversation] Looking for conversation with participants:', sortedParticipants);
  
  // Try to find existing conversation
  let conversation = await Conversation.findOne({ 
    participants: { $all: sortedParticipants, $size: sortedParticipants.length }
  });
  
  if (!conversation) {
    console.log('[conversation] No existing conversation found, creating new one...');
    try {
      conversation = await Conversation.create({
        participants: sortedParticipants,
        lastMessage: { text: '', from: null, timestamp: new Date() },
        unreadCount: new Map()
      });
      console.log('[conversation] ✅ Successfully created new conversation:', conversation._id);
    } catch (error) {
      if (error.code === 11000) {
        // Duplicate key error - conversation already exists, try to find it again
        console.log('[conversation] Duplicate key error, searching for existing conversation...');
        conversation = await Conversation.findOne({ 
          participants: { $all: sortedParticipants, $size: sortedParticipants.length }
        });
        if (!conversation) {
          throw new Error('Failed to create or find conversation');
        }
        console.log('[conversation] Found existing conversation after duplicate error:', conversation._id);
      } else {
        console.error('[conversation] Error creating conversation:', error);
        throw error;
      }
    }
  } else {
    console.log('[conversation] Found existing conversation:', conversation._id);
  }
  
  return conversation;
};

const updateConversationLastMessage = async (conversationId, messageData) => {
  await Conversation.findByIdAndUpdate(conversationId, {
    lastMessage: {
      text: messageData.text,
      from: messageData.from,
      timestamp: messageData.createdAt
    }
  });
};

const incrementUnreadCount = async (conversationId, userId) => {
  await Conversation.findByIdAndUpdate(conversationId, {
    $inc: { [`unreadCount.${userId}`]: 1 }
  });
};

const resetUnreadCount = async (conversationId, userId) => {
  await Conversation.findByIdAndUpdate(conversationId, {
    $set: { [`unreadCount.${userId}`]: 0 }
  });
};

// --- helpers/auth ---
const signToken = (user) =>
  jwt.sign({ sub: user._id.toString(), email: user.email, name: user.name }, JWT_SECRET, { expiresIn: '7d' });

const auth = (req, res, next) => {
  const header = req.headers.authorization || '';
  const [type, token] = header.split(' ');
  if (type !== 'Bearer' || !token) return res.status(401).json({ error: 'Unauthorized' });
  try { req.user = jwt.verify(token, JWT_SECRET); next(); }
  catch { return res.status(401).json({ error: 'Invalid token' }); }
};

// Enhanced auth middleware that validates user exists in database
const authWithUserValidation = async (req, res, next) => {
  const header = req.headers.authorization || '';
  const [type, token] = header.split(' ');
  if (type !== 'Bearer' || !token) return res.status(401).json({ error: 'Unauthorized' });
  
  try { 
    const decoded = jwt.verify(token, JWT_SECRET);
    
    // Verify user still exists in database
    const user = await User.findById(decoded.sub).select('_id name email');
    if (!user) {
      console.log('[auth] User not found in database:', decoded.sub);
      return res.status(401).json({ error: 'User not found' });
    }
    
    req.user = decoded;
    req.userData = user; // Add user data to request
    next();
  }
  catch (e) { 
    console.log('[auth] Token verification failed:', e.message);
    return res.status(401).json({ error: 'Invalid token' }); 
  }
};

// Validate that a user ID exists in database
const validateUserExists = async (userId) => {
  try {
    const user = await User.findById(userId).select('_id name email');
    if (!user) {
      console.log('[validation] User not found:', userId);
      return null;
    }
    return user;
  } catch (e) {
    console.log('[validation] Error validating user:', userId, e.message);
    return null;
  }
};

// --- REST routes ---
app.get('/health', (_req, res) => res.json({ ok: true }));

app.post('/api/register', async (req, res) => {
  try {
    const { name, email, phone, password } = req.body || {};
    if (!name || !email || !password) return res.status(400).json({ error: 'name, email, password are required' });
    if (!validator.isEmail(email)) return res.status(400).json({ error: 'Invalid email' });
    if (String(password).length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });

    const exists = await User.findOne({ email: email.toLowerCase() }).lean();
    if (exists) return res.status(409).json({ error: 'Email already registered' });

    const passwordHash = await bcrypt.hash(password, 12);
    const newUser = await User.create({ name: name.trim(), email: email.toLowerCase(), phone: phone ?? null, passwordHash });
    
    console.log('[register] New user created:', {
      id: String(newUser._id),
      name: newUser.name,
      email: newUser.email
    });
    
    return res.status(201).json({ message: 'User created' });
  } catch (e) {
    if (e?.code === 11000) return res.status(409).json({ error: 'Email already registered' });
    console.error('[register]', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'email & password required' });

    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ error: 'Incorrect credentials' });

    console.log('[login] User logged in:', {
      id: String(user._id),
      name: user.name,
      email: user.email
    });

    const token = signToken(user);
    return res.json({ token });
  } catch (e) {
    console.error('[login]', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/me', authWithUserValidation, async (req, res) => {
  return res.json({ user: req.userData });
});

// Threads list (by conversations)
app.get('/api/threads', authWithUserValidation, async (req, res) => {
  try {
    const userId = new mongoose.Types.ObjectId(req.user.sub);
    
    const conversations = await Conversation.find({
      participants: userId
    })
    .populate('participants', 'name email')
    .populate('lastMessage.from', 'name')
    .sort({ 'lastMessage.timestamp': -1 })
    .lean();

    const threads = conversations.map(conv => {
      const otherParticipant = conv.participants.find(p => p._id.toString() !== userId.toString());
      // Handle unreadCount as both Map and plain object (when using .lean())
      const unreadCount = conv.unreadCount instanceof Map 
        ? conv.unreadCount.get(userId.toString()) || 0
        : conv.unreadCount?.[userId.toString()] || 0;
      
      return {
        conversationId: conv._id,
        peerId: otherParticipant._id,
        name: otherParticipant.name,
        email: otherParticipant.email,
        lastMessage: conv.lastMessage.text,
        lastAt: conv.lastMessage.timestamp,
        unreadCount
      };
    });

    res.json({ threads });
  } catch (e) {
    console.error('[threads] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Messages with a peer
app.get('/api/messages', authWithUserValidation, async (req, res) => {
  try {
    const { peerId, peerEmail, conversationId, limit = 30, before } = req.query;
    const meId = new mongoose.Types.ObjectId(req.user.sub);

    let conversation;
    let peer;

    if (conversationId) {
      // Get messages by conversation ID
      conversation = await Conversation.findById(conversationId);
      if (!conversation) {
        console.log('[api/messages] Conversation not found:', conversationId);
        return res.status(404).json({ error: 'Conversation not found' });
      }
      
      // Validate that current user is a participant
      const isParticipant = conversation.participants.some(p => p.toString() === meId.toString());
      if (!isParticipant) {
        console.log('[api/messages] User not a participant:', {
          conversationId,
          userId: meId.toString(),
          participants: conversation.participants.map(p => p.toString())
        });
        return res.status(404).json({ error: 'Conversation not found' });
      }
      
      // Get the other participant and validate they exist
      const otherParticipantId = conversation.participants.find(p => p.toString() !== meId.toString());
      peer = await User.findById(otherParticipantId).select('_id name email');
      
      if (!peer) {
        console.log('[api/messages] Other participant not found:', otherParticipantId);
        return res.status(404).json({ error: 'Conversation participant not found' });
      }
    } else if (peerId || peerEmail) {
      // Get or create conversation by peer
      if (peerId) {
        peer = await User.findById(peerId).select('_id name email');
      } else {
        peer = await User.findOne({ email: String(peerEmail).toLowerCase() }).select('_id name email');
      }
      
      if (!peer) return res.status(404).json({ error: 'Peer not found' });
      
      conversation = await getOrCreateConversation([meId, peer._id]);
    } else {
      return res.status(400).json({ error: 'peerId, peerEmail, or conversationId required' });
    }

    // Get messages for the conversation
    const q = { conversationId: conversation._id };
    if (before) q.createdAt = { $lt: new Date(before) };

    const list = await Message.find(q)
      .sort({ createdAt: -1 })
      .limit(Math.min(Number(limit) || 30, 100))
      .lean();
    
    const messages = list.reverse().map(m => ({ ...m, sender: m.from, receiver: m.to }));
    
    // Reset unread count for this user
    await resetUnreadCount(conversation._id, meId.toString());
    
    res.json({ peer, messages, conversationId: conversation._id });
  } catch (e) {
    console.error('[messages:list]', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

// File upload endpoint
app.post('/api/upload', auth, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const fileInfo = {
      fileName: req.file.originalname,
      filePath: req.file.path,
      fileSize: req.file.size,
      mimeType: req.file.mimetype,
      url: `/uploads/${req.file.filename}`
    };

    res.json({ file: fileInfo });
  } catch (e) {
    console.error('[upload] error', e);
    res.status(500).json({ error: 'Upload failed' });
  }
});

// Send message (HTTP) → DB save + broadcast
app.post('/api/messages', authWithUserValidation, async (req, res) => {
  try {
    const { toId, toEmail, text, messageType, fileAttachment } = req.body || {};
    if (!text && !fileAttachment) return res.status(400).json({ error: 'Text or file required' });

    // Validate sender exists in database
    const sender = await validateUserExists(req.user.sub);
    if (!sender) {
      console.warn('[api/messages] Sender not found in database:', req.user.sub);
      return res.status(401).json({ error: 'Sender not found' });
    }

    // Validate receiver exists in database
    let peer = null;
    if (toId) {
      peer = await validateUserExists(toId);
    } else if (toEmail) {
      peer = await User.findOne({ email: String(toEmail).toLowerCase() }).select('_id name email');
    }
    
    if (!peer) {
      console.warn('[api/messages] Peer not found or not registered:', { toId, toEmail });
      return res.status(404).json({ error: 'Peer not found or not registered' });
    }

    // Prevent self-messaging
    if (String(sender._id) === String(peer._id)) {
      return res.status(400).json({ error: 'Cannot send message to yourself' });
    }

    const senderId = new mongoose.Types.ObjectId(sender._id);
    const receiverId = new mongoose.Types.ObjectId(peer._id);

    console.log('[api/messages] Message details:', {
      senderId: String(senderId),
      receiverId: String(receiverId),
      senderName: sender.name,
      senderEmail: sender.email,
      receiverName: peer.name,
      receiverEmail: peer.email,
      text: text
    });

    // Get or create conversation
    console.log('[api/messages] Getting or creating conversation for participants:', [senderId, receiverId]);
    const conversation = await getOrCreateConversation([senderId, receiverId]);
    console.log('[api/messages] Using conversation:', conversation._id);

    // Create message with conversation ID
    const msg = await Message.create({ 
      conversationId: conversation._id,
      from: senderId, 
      to: receiverId, 
      text: text ? String(text).trim() : '',
      messageType: messageType || 'text',
      fileAttachment: fileAttachment || undefined,
      status: 'sent' 
    });

    // Update conversation last message
    let lastMessageText = msg.text;
    if (msg.messageType === 'image') {
      lastMessageText = '📷 Photo';
    } else if (msg.messageType === 'multi_image') {
      lastMessageText = `📷 ${msg.fileAttachment?.count || 1} Photos`;
    } else if (msg.messageType === 'file') {
      lastMessageText = `📎 ${msg.fileAttachment?.fileName || 'File'}`;
    }
    
    await updateConversationLastMessage(conversation._id, {
      text: lastMessageText,
      from: msg.from,
      createdAt: msg.createdAt
    });

    // Increment unread count for receiver
    await incrementUnreadCount(conversation._id, receiverId.toString());

    const payload = { 
      _id: msg._id, 
      conversationId: conversation._id,
      from: msg.from, 
      to: msg.to, 
      sender: msg.from, 
      receiver: msg.to, 
      text: msg.text, 
      messageType: msg.messageType,
      fileAttachment: msg.fileAttachment,
      status: msg.status, 
      createdAt: msg.createdAt 
    };
    
    // Broadcast to sender and receiver via Socket.IO
    io.to(String(msg.from)).emit('message:new', payload);
    io.to(String(msg.to)).emit('message:new', payload);
    
    // Emit thread updates
    io.to(String(msg.from)).emit('thread:update', { 
      conversationId: conversation._id,
      peerId: String(msg.to) 
    });
    io.to(String(msg.to)).emit('thread:update', { 
      conversationId: conversation._id,
      peerId: String(msg.from) 
    });

    console.log('[api/messages] saved', { 
      id: String(msg._id), 
      conversationId: conversation._id,
      from: String(msg.from),
      to: String(msg.to),
      fromEmail: req.user.email,
      toName: peer.name,
      text: msg.text
    });
    return res.status(201).json({ message: payload, conversationId: conversation._id });
  } catch (e) {
    console.error('[api/messages] error', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

// --- Socket.IO server ---
const httpServer = http.createServer(app);
const io = new SocketIOServer(httpServer, { 
  cors: { 
    origin: true, 
    methods: ['GET','POST'],
    credentials: true
  },
  transports: ['websocket', 'polling']
});

// Store connected users for easy access
const connectedUsers = new Map();

// Socket auth with database validation
io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token || socket.handshake.query?.token;
  console.log('[socket auth] Attempting authentication with token:', token ? 'present' : 'missing');
  
  if (!token) {
    console.log('[socket auth] No token provided');
    return next(new Error('no token'));
  }
  
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    console.log('[socket auth] Token decoded successfully for user:', decoded.sub);
    
    // Verify user still exists in database
    const user = await User.findById(decoded.sub).select('_id name email');
    if (!user) {
      console.log('[socket auth] User not found in database:', decoded.sub);
      return next(new Error('user not found'));
    }
    
    socket.data.userId = user._id.toString();
    socket.data.userEmail = user.email;
    socket.data.userName = user.name;
    console.log('[socket auth] Authentication successful for user:', user.email);
    return next();
  } catch (e) { 
    console.error('[socket auth] token verification failed:', e.message);
    return next(new Error('bad token')); 
  }
});

io.on('connection', (socket) => {
  const userId = String(socket.data.userId);
  const userEmail = socket.data.userEmail;
  
  // Store connected user
  connectedUsers.set(userId, {
    socketId: socket.id,
    email: userEmail,
    name: socket.data.userName,
    connectedAt: new Date()
  });
  
  // Join user's personal room for receiving messages
  socket.join(userId);
  console.log('[socket] connected', { userId, userEmail, socketId: socket.id });
  
  // Handle connection errors
  socket.on('error', (error) => {
    console.error('[socket] connection error:', { userId, userEmail, error: error.message });
  });

  // Socket-only send → DB save + broadcast
  socket.on('message:send', async (payload, ack) => {
    try {
      const { toId, toEmail, text, messageType, fileAttachment } = payload || {};
      if (!text && !fileAttachment) return ack?.({ error: 'Text or file required' });

      // Validate sender exists in database (double-check since we already validated in auth)
      const sender = await validateUserExists(socket.data.userId);
      if (!sender) {
        console.warn('[socket message:send] Sender not found in database:', socket.data.userId);
        return ack?.({ error: 'Sender not found - please re-authenticate' });
      }

      // Validate receiver exists in database
      let peer = null;
      if (toId) {
        peer = await validateUserExists(toId);
      } else if (toEmail) {
        peer = await User.findOne({ email: String(toEmail).toLowerCase() }).select('_id name email');
      }
      
      if (!peer) {
        console.warn('[socket message:send] Peer not found or not registered:', { toId, toEmail });
        return ack?.({ error: 'Peer not found or not registered' });
      }

      // Prevent self-messaging
      if (String(sender._id) === String(peer._id)) {
        return ack?.({ error: 'Cannot send message to yourself' });
      }

      const senderId = new mongoose.Types.ObjectId(sender._id);
      const receiverId = new mongoose.Types.ObjectId(peer._id);

      console.log('[socket message:send] Message details:', {
        senderId: String(senderId),
        receiverId: String(receiverId),
        senderName: sender.name,
        senderEmail: sender.email,
        receiverName: peer.name,
        receiverEmail: peer.email,
        text: text
      });

      // Get or create conversation
      console.log('[socket message:send] Getting or creating conversation for participants:', [senderId, receiverId]);
      const conversation = await getOrCreateConversation([senderId, receiverId]);
      console.log('[socket message:send] Using conversation:', conversation._id);

      // Create message in database
      const msg = await Message.create({ 
        conversationId: conversation._id,
        from: senderId, 
        to: receiverId, 
        text: text ? String(text).trim() : '',
        messageType: messageType || 'text',
        fileAttachment: fileAttachment || undefined,
        status: 'sent' 
      });

      // Update conversation last message
      let lastMessageText = msg.text;
      if (msg.messageType === 'image') {
        lastMessageText = '📷 Photo';
      } else if (msg.messageType === 'multi_image') {
        lastMessageText = `📷 ${msg.fileAttachment?.count || 1} Photos`;
      } else if (msg.messageType === 'file') {
        lastMessageText = `📎 ${msg.fileAttachment?.fileName || 'File'}`;
      }
        
      await updateConversationLastMessage(conversation._id, {
        text: lastMessageText,
        from: msg.from,
        createdAt: msg.createdAt
      });

      // Increment unread count for receiver
      await incrementUnreadCount(conversation._id, receiverId.toString());

      // Prepare message payload
      const messagePayload = { 
        _id: msg._id, 
        conversationId: conversation._id,
        from: msg.from, 
        to: msg.to, 
        sender: msg.from, 
        receiver: msg.to, 
        text: msg.text, 
        messageType: msg.messageType,
        fileAttachment: msg.fileAttachment,
        status: msg.status, 
        createdAt: msg.createdAt 
      };

      // Broadcast to sender and receiver
      socket.emit('message:new', messagePayload);
      io.to(String(receiverId)).emit('message:new', messagePayload);
      
      // Emit thread updates
      socket.emit('thread:update', { 
        conversationId: conversation._id,
        peerId: String(receiverId) 
      });
      io.to(String(receiverId)).emit('thread:update', { 
        conversationId: conversation._id,
        peerId: String(senderId) 
      });

      console.log('[socket message:send] saved and broadcasted', { 
        id: String(msg._id), 
        from: String(msg.from),
        to: String(msg.to),
        fromName: socket.data.userName,
        toName: peer.name,
        text: msg.text
      });
      
      return ack?.({ ok: true, message: messagePayload });
    } catch (e) {
      console.error('[socket message:send] error', e);
      return ack?.({ error: 'Server error' });
    }
  });

  // Handle typing indicators
  socket.on('typing:start', (data) => {
    const { toId } = data;
    if (toId) {
      io.to(String(toId)).emit('typing:start', { fromId: userId });
    }
  });

  socket.on('typing:stop', (data) => {
    const { toId } = data;
    if (toId) {
      io.to(String(toId)).emit('typing:stop', { fromId: userId });
    }
  });

  // Handle message read receipts
  socket.on('message:read', async (data) => {
    try {
      const { messageId } = data;
      if (!messageId) return;

      const message = await Message.findById(messageId);
      if (message && String(message.to) === userId) {
        message.status = 'read';
        message.seenAt = new Date();
        await message.save();
        
        // Notify sender that message was read
        io.to(String(message.from)).emit('message:read', { 
          messageId, 
          readBy: userId 
        });
      }
    } catch (e) {
      console.error('[socket message:read] error', e);
    }
  });

  socket.on('disconnect', () => {
    connectedUsers.delete(userId);
    console.log('[socket] disconnected', { userId, userEmail });
  });
});

// Helper function to get connected users
const getConnectedUsers = () => {
  return Array.from(connectedUsers.entries()).map(([userId, data]) => ({
    userId,
    ...data
  }));
};

// Add endpoint to get connected users
app.get('/api/connected-users', auth, (req, res) => {
  const connectedUsersList = getConnectedUsers();
  res.json({ connectedUsers: connectedUsersList });
});

// Add endpoint to get online status of specific users
app.get('/api/users/:userId/status', auth, (req, res) => {
  const { userId } = req.params;
  const isOnline = connectedUsers.has(userId);
  const userData = connectedUsers.get(userId);
  
  
  res.json({ 
    userId, 
    isOnline, 
    lastSeen: userData?.connectedAt || null 
  });
});

// Debug endpoint to check token and user validation
app.get('/api/debug/token', authWithUserValidation, async (req, res) => {
  try {
    const tokenUser = req.user;
    const dbUser = req.userData;
    
    res.json({
      token: {
        sub: tokenUser.sub,
        email: tokenUser.email,
        name: tokenUser.name,
        iat: tokenUser.iat,
        exp: tokenUser.exp
      },
      database: {
        id: String(dbUser._id),
        email: dbUser.email,
        name: dbUser.name
      },
      match: {
        idMatch: tokenUser.sub === String(dbUser._id),
        emailMatch: tokenUser.email === dbUser.email,
        nameMatch: tokenUser.name === dbUser.name
      },
      connectedUsers: getConnectedUsers().filter(u => u.userId === String(dbUser._id))
    });
  } catch (e) {
    console.error('[debug:token] error:', e);
    res.status(500).json({ error: 'Debug check failed' });
  }
});

// Create a new conversation between two users
app.post('/api/conversations', authWithUserValidation, async (req, res) => {
  try {
    const { peerId } = req.body || {};
    if (!peerId) return res.status(400).json({ error: 'peerId is required' });

    // Validate current user exists
    const currentUser = await validateUserExists(req.user.sub);
    if (!currentUser) {
      return res.status(401).json({ error: 'Current user not found' });
    }

    // Validate peer user exists
    const peer = await validateUserExists(peerId);
    if (!peer) {
      return res.status(404).json({ error: 'Peer user not found or not registered' });
    }

    // Prevent self-conversation
    if (String(currentUser._id) === String(peer._id)) {
      return res.status(400).json({ error: 'Cannot create conversation with yourself' });
    }

    const currentUserId = new mongoose.Types.ObjectId(currentUser._id);
    const peerUserId = new mongoose.Types.ObjectId(peer._id);
    
    console.log('[api/conversations] Creating conversation between:', {
      currentUser: { id: String(currentUserId), name: currentUser.name },
      peer: { id: String(peerUserId), name: peer.name }
    });
    
    const conversation = await getOrCreateConversation([currentUserId, peerUserId]);
    
    res.json({ 
      conversationId: conversation._id,
      participants: [currentUserId, peerUserId],
      peer: peer
    });
  } catch (e) {
    console.error('[api/conversations] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Check database status endpoint
app.get('/api/admin/status', authWithUserValidation, async (req, res) => {
  try {
    console.log('[admin] Database status requested by:', req.userData.name);
    
    // Get all users
    const allUsers = await User.find({}).select('_id name email createdAt').lean();
    
    // Get all conversations
    const allConversations = await Conversation.find({}).lean();
    
    // Check for problematic conversations
    const problematicConversations = [];
    for (const conv of allConversations) {
      const validParticipants = [];
      const invalidParticipants = [];
      
      for (const participantId of conv.participants) {
        const user = await User.findById(participantId);
        if (user) {
          validParticipants.push({
            id: String(participantId),
            name: user.name,
            email: user.email
          });
        } else {
          invalidParticipants.push(String(participantId));
        }
      }
      
      if (invalidParticipants.length > 0 || validParticipants.length < 2) {
        problematicConversations.push({
          conversationId: String(conv._id),
          validParticipants,
          invalidParticipants,
          lastMessage: conv.lastMessage,
          createdAt: conv.createdAt
        });
      }
    }
    
    // Get message count
    const messageCount = await Message.countDocuments();
    
    res.json({
      users: {
        total: allUsers.length,
        list: allUsers.map(u => ({
          id: String(u._id),
          name: u.name,
          email: u.email,
          createdAt: u.createdAt
        }))
      },
      conversations: {
        total: allConversations.length,
        problematic: problematicConversations.length,
        problematicList: problematicConversations
      },
      messages: {
        total: messageCount
      }
    });
  } catch (e) {
    console.error('[admin] Status check error:', e);
    res.status(500).json({ error: 'Status check failed' });
  }
});

// Database cleanup endpoint (for development/testing)
app.post('/api/admin/cleanup', authWithUserValidation, async (req, res) => {
  try {
    // Only allow cleanup if user is admin (you can add admin check here)
    console.log('[admin] Database cleanup requested by:', req.userData.name);
    
    // Clean up orphaned conversations (conversations with non-existent users)
    const allConversations = await Conversation.find({}).lean();
    let cleanedConversations = 0;
    
    for (const conv of allConversations) {
      const validParticipants = [];
      for (const participantId of conv.participants) {
        const user = await User.findById(participantId);
        if (user) {
          validParticipants.push(participantId);
        }
      }
      
      if (validParticipants.length !== conv.participants.length) {
        if (validParticipants.length < 2) {
          // Delete conversation if less than 2 valid participants
          await Conversation.findByIdAndDelete(conv._id);
          await Message.deleteMany({ conversationId: conv._id });
          cleanedConversations++;
        } else {
          // Update conversation with valid participants only
          await Conversation.findByIdAndUpdate(conv._id, { participants: validParticipants });
        }
      }
    }
    
    // Clean up orphaned messages
    const orphanedMessages = await Message.find({
      $or: [
        { conversationId: { $exists: false } },
        { from: { $exists: false } },
        { to: { $exists: false } }
      ]
    });
    
    if (orphanedMessages.length > 0) {
      await Message.deleteMany({
        $or: [
          { conversationId: { $exists: false } },
          { from: { $exists: false } },
          { to: { $exists: false } }
        ]
      });
    }
    
    res.json({ 
      message: 'Database cleanup completed',
      cleanedConversations,
      orphanedMessages: orphanedMessages.length
    });
  } catch (e) {
    console.error('[admin] Cleanup error:', e);
    res.status(500).json({ error: 'Cleanup failed' });
  }
});

// Add endpoint to get conversation details
app.get('/api/conversations/:conversationId', auth, async (req, res) => {
  try {
    const { conversationId } = req.params;
    const userId = new mongoose.Types.ObjectId(req.user.sub);
    
    const conversation = await Conversation.findById(conversationId)
      .populate('participants', 'name email')
      .populate('lastMessage.from', 'name')
      .lean();
    
    if (!conversation) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    if (!conversation.participants.some(p => p._id.toString() === userId.toString())) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const otherParticipant = conversation.participants.find(p => p._id.toString() !== userId.toString());
    
    // Handle unreadCount as both Map and plain object (when using .lean())
    const unreadCount = conversation.unreadCount instanceof Map 
      ? conversation.unreadCount.get(userId.toString()) || 0
      : conversation.unreadCount?.[userId.toString()] || 0;
    
    res.json({
      conversation: {
        id: conversation._id,
        participants: conversation.participants,
        lastMessage: conversation.lastMessage,
        unreadCount,
        isGroup: conversation.isGroup,
        groupName: conversation.groupName,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt
      },
      peer: otherParticipant
    });
  } catch (e) {
    console.error('[conversation:get] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Search users endpoint
app.get('/api/users/search', auth, async (req, res) => {
  try {
    const { q, limit = 20 } = req.query;
    const currentUserId = new mongoose.Types.ObjectId(req.user.sub);
    
    if (!q || q.trim().length < 2) {
      return res.status(400).json({ error: 'Search query must be at least 2 characters' });
    }
    
    const searchQuery = {
      _id: { $ne: currentUserId }, // Exclude current user
      $or: [
        { name: { $regex: q.trim(), $options: 'i' } },
        { email: { $regex: q.trim(), $options: 'i' } }
      ]
    };
    
    const users = await User.find(searchQuery)
      .select('_id name email createdAt')
      .limit(Math.min(Number(limit), 50))
      .sort({ name: 1 })
      .lean();
    
    res.json({ users });
  } catch (e) {
    console.error('[users:search] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get all users (for user discovery)
app.get('/api/users', auth, async (req, res) => {
  try {
    const { limit = 50, offset = 0 } = req.query;
    const currentUserId = new mongoose.Types.ObjectId(req.user.sub);
    
    const users = await User.find({ _id: { $ne: currentUserId } })
      .select('_id name email createdAt')
      .limit(Math.min(Number(limit), 100))
      .skip(Number(offset))
      .sort({ name: 1 })
      .lean();
    
    const total = await User.countDocuments({ _id: { $ne: currentUserId } });
    
    // Debug: Log all users in database
    console.log('[users:list] All users in database:', users.map(u => ({
      id: String(u._id),
      name: u.name,
      email: u.email
    })));
    
    res.json({ 
      users, 
      total,
      hasMore: (Number(offset) + users.length) < total
    });
  } catch (e) {
    console.error('[users:list] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get user by ID
app.get('/api/users/:userId', auth, async (req, res) => {
  try {
    const { userId } = req.params;
    const currentUserId = new mongoose.Types.ObjectId(req.user.sub);
    
    if (userId === currentUserId.toString()) {
      return res.status(400).json({ error: 'Cannot get own profile via this endpoint' });
    }
    
    const user = await User.findById(userId)
      .select('_id name email createdAt')
      .lean();
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Check if there's an existing conversation
    const participantIds = [currentUserId, new mongoose.Types.ObjectId(userId)];
    console.log('[user:get] Checking for existing conversation between participants:', participantIds);
    
    const conversation = await Conversation.findOne({
      participants: { $all: participantIds, $size: participantIds.length }
    }).lean();
    
    if (conversation) {
      console.log('[user:get] Found existing conversation:', conversation._id);
    } else {
      console.log('[user:get] No existing conversation found - participants are not peering');
    }
    
    res.json({ 
      user,
      existingConversationId: conversation?._id || null
    });
  } catch (e) {
    console.error('[user:get] error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// --- Error handling middleware ---
// 404 handler for undefined routes
app.use('*', (req, res) => {
  res.status(404).json({ 
    error: 'Route not found', 
    path: req.originalUrl,
    method: req.method 
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('[Global Error Handler]', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: err.message || 'Something went wrong'
  });
});

// --- start ---
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`[api] http & ws on http://0.0.0.0:${PORT}`);
  console.log(`[socket] Socket.IO server ready for real-time messaging`);
});

// graceful shutdown
const shutdown = async (sig) => {
  console.log('\n[shutdown]', sig);
  httpServer.close();
  await mongoose.connection.close();
  process.exit(0);
};
['SIGINT','SIGTERM'].forEach(s => process.on(s, () => shutdown(s)));
