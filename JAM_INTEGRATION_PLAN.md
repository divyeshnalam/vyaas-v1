# JAM (Just A Minute) Integration Plan

## Project Overview

JAM (Just A Minute) is a speech assessment service that integrates with the existing VyaasaCampus platform. Students will participate in timed speech sessions where they receive topics, prepare, and deliver speeches that are evaluated by AI.

## Architecture Overview

### System Components
- **Phoenix Backend**: Session management, API endpoints, real-time updates
- **Python JAM Service**: Topic generation, speech processing, AI evaluation
- **Frontend**: LiveView with WebRTC audio recording
- **Database**: Multi-tenant schema with session tracking
- **WebSocket**: Real-time communication for live updates

### Authentication Strategy
- **JAM_SECRET**: Shared secret environment variable for service-to-service authentication
- **Student JWT**: Regular JWT authentication for student endpoints
- **Tenant Isolation**: Multi-tenant schema isolation following existing patterns

## Database Schema

### **jam_sessions Table**
```sql
CREATE TABLE jam_sessions (
    -- Primary identifiers
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    
    -- Session management
    session_token VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'created',
    
    -- Topic information
    topic_title TEXT,
    topic_explanation TEXT,
    topic_changed BOOLEAN DEFAULT FALSE,
    change_topic_available BOOLEAN DEFAULT TRUE,
    
    -- Audio and recording
    recording_file_path TEXT,
    recording_duration_seconds INTEGER,
    recording_active BOOLEAN DEFAULT FALSE,
    
    -- Speech processing
    transcript TEXT,
    word_count INTEGER,
    speech_duration_seconds INTEGER,
    
    -- AI Evaluation (stored as JSON)
    evaluation_data JSONB,
    final_score INTEGER, -- 0-100
    clarity_score INTEGER, -- 1-10
    structure_score INTEGER, -- 1-10
    relevance_score INTEGER, -- 1-10
    impact_score INTEGER, -- 1-10
    confidence_score INTEGER, -- 1-10
    overall_summary TEXT,
    
    -- Timing information
    decision_time_seconds INTEGER DEFAULT 60,
    preparation_time_seconds INTEGER DEFAULT 15,
    speech_time_seconds INTEGER DEFAULT 60,
    actual_decision_time_used INTEGER,
    actual_preparation_time_used INTEGER,
    actual_speech_time_used INTEGER,
    
    -- WebRTC and technical
    webrtc_connected BOOLEAN DEFAULT FALSE,
    audio_quality_score DECIMAL(3,2),
    noise_level DECIMAL(3,2),
    
    -- Error handling
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);
```

## Session Lifecycle

### Status Flow
1. **created** → Session created, waiting for topic generation
2. **topic_generated** → Topic received from Python service
3. **decision_phase** → Student deciding on topic (60 seconds)
4. **preparation** → Student preparing speech (15 seconds)
5. **speaking** → Student delivering speech (60 seconds)
6. **processing** → Python service processing audio
7. **completed** → Evaluation complete, results available
8. **failed** → Error occurred, can retry if retry_count < 3

## API Endpoints

### Student JAM Endpoints
```
POST   /api/student/jam/sessions                    # Create new JAM session
GET    /api/student/jam/sessions/:id                # Get session details
PUT    /api/student/jam/sessions/:id                # Update session
POST   /api/student/jam/sessions/:id/start          # Start session
POST   /api/student/jam/sessions/:id/decide-topic   # Make topic decision
POST   /api/student/jam/sessions/:id/start-preparation # Start preparation
POST   /api/student/jam/sessions/:id/start-speaking # Start speaking
POST   /api/student/jam/sessions/:id/upload-audio   # Upload audio
GET    /api/student/jam/sessions/:id/status         # Get session status
GET    /api/student/jam/sessions/:id/results        # Get evaluation results
```

### JAM Callback Endpoints (Python Service)
```
POST   /api/jam/callback/topic-generated    # Topic generation complete
POST   /api/jam/callback/audio-processed    # Audio processing complete
POST   /api/jam/callback/processing-error   # Processing error occurred
POST   /api/jam/callback/status-update      # Status update from service
POST   /api/jam/callback/retry-session      # Retry failed session
GET    /api/jam/callback/health             # Health check
```

## Authentication & Security

### JAM Service Authentication
- **Shared Secret**: `JAM_SECRET` environment variable
- **Bearer Token**: `Authorization: Bearer <JAM_SECRET>`
- **Service-to-Service**: Python service authenticates with Phoenix
- **Student Authentication**: Regular JWT for student endpoints

### Security Measures
- Tenant isolation using schema prefixes
- Session token validation
- Rate limiting on session creation
- Audio file validation and sanitization
- Input validation and sanitization

## File Structure

### Backend Files Created
```
lib/vyaasa_campus/
├── schema/jam/
│   └── jam_session.ex                    # Ecto schema and changesets
├── contexts/
│   └── jam.ex                           # Business logic and Python service integration
└── priv/repo/tenant_migrations/
    └── 20241220000001_create_jam_sessions.exs  # Database migration

lib/vyaasa_campus_web/
├── controllers/api/
│   ├── student/
│   │   └── jam_controller.ex            # Student JAM endpoints
│   └── jam_callback_controller.ex       # Python service callbacks
├── plugs/
│   └── jam_callback_auth.ex             # JAM service authentication
└── router.ex                            # Updated with JAM routes
```

## Configuration

### Environment Variables
```bash
# JAM Service Configuration
JAM_SECRET=your_shared_secret_here
PYTHON_BASE_URL=http://localhost:8000  # Python JAM service URL
```

### Runtime Configuration
```elixir
# config/runtime.exs
config :vyaasa_campus,
  jam_secret: System.get_env("JAM_SECRET"),
  python_base_url: System.get_env("PYTHON_BASE_URL", "http://localhost:8000")
```

## Implementation Steps

### Phase 1: Backend Foundation
- [x] Database migration for jam_sessions table
- [x] Ecto schema with comprehensive changesets
- [x] Context module with business logic
- [x] Student API controller
- [x] JAM callback controller
- [x] Authentication plug
- [x] Router configuration

### Phase 2: Python Service Integration
- [ ] Python JAM service development
- [ ] Topic generation API
- [ ] Audio processing API
- [ ] AI evaluation engine
- [ ] Callback implementation

### Phase 3: Frontend Development
- [ ] JAM session LiveView
- [ ] WebRTC audio recording
- [ ] Real-time status updates
- [ ] Results display
- [ ] Session history

### Phase 4: Testing & Deployment
- [ ] Unit tests for all modules
- [ ] Integration tests
- [ ] End-to-end testing
- [ ] Performance optimization
- [ ] Production deployment

## API Request/Response Examples

### Create JAM Session
```json
POST /api/student/jam/sessions
{
  "jam_session": {
    "preferences": {
      "difficulty": "medium",
      "topics": ["technology", "education"]
    }
  }
}

Response:
{
  "jam_session": {
    "id": "uuid",
    "session_token": "token",
    "status": "created",
    "decision_time_seconds": 60,
    "preparation_time_seconds": 15,
    "speech_time_seconds": 60
  },
  "message": "JAM session created successfully. Topic generation in progress."
}
```

### Topic Decision
```json
POST /api/student/jam/sessions/:id/decide-topic
{
  "decision": {
    "topic_changed": false,
    "actual_decision_time_used": 45
  }
}

Response:
{
  "jam_session": {
    "id": "uuid",
    "status": "decision_phase",
    "topic_title": "The Future of Artificial Intelligence",
    "topic_explanation": "Discuss the potential impact of AI on society..."
  },
  "message": "Topic decision recorded successfully"
}
```

### Audio Upload
```json
POST /api/student/jam/sessions/:id/upload-audio
{
  "audio_data": {
    "recording_file_path": "/uploads/audio/session_123.wav",
    "recording_duration_seconds": 58,
    "speech_time_used": 58,
    "audio_quality_score": 0.95,
    "noise_level": 0.05
  }
}

Response:
{
  "jam_session": {
    "id": "uuid",
    "status": "processing"
  },
  "message": "Audio uploaded successfully. Processing in progress."
}
```

### Results Retrieval
```json
GET /api/student/jam/sessions/:id/results

Response:
{
  "jam_session": {
    "id": "uuid",
    "status": "completed",
    "completed_at": "2024-12-20T10:30:00Z"
  },
  "results": {
    "final_score": 85,
    "clarity_score": 8,
    "structure_score": 9,
    "relevance_score": 8,
    "impact_score": 7,
    "confidence_score": 9,
    "overall_summary": "Excellent speech with clear structure and good relevance to the topic...",
    "transcript": "The future of artificial intelligence is a topic that...",
    "word_count": 245,
    "speech_duration_seconds": 58
  }
}
```

## Python Service Callbacks

### Topic Generated Callback
```json
POST /api/jam/callback/topic-generated
{
  "session_token": "token",
  "topic_data": {
    "title": "The Future of Artificial Intelligence",
    "explanation": "Discuss the potential impact of AI on society...",
    "change_topic_available": true
  }
}
```

### Audio Processed Callback
```json
POST /api/jam/callback/audio-processed
{
  "session_token": "token",
  "evaluation_data": {
    "transcript": "The future of artificial intelligence is a topic that...",
    "word_count": 245,
    "speech_duration_seconds": 58,
    "final_score": 85,
    "clarity_score": 8,
    "structure_score": 9,
    "relevance_score": 8,
    "impact_score": 7,
    "confidence_score": 9,
    "overall_summary": "Excellent speech with clear structure...",
    "evaluation_data": {
      "detailed_analysis": "...",
      "improvement_suggestions": "..."
    }
  }
}
```

## Testing Strategy

### Unit Tests
- Schema validation and changesets
- Context business logic
- Controller request/response handling
- Authentication plug validation

### Integration Tests
- End-to-end session lifecycle
- Python service integration
- Database operations
- Error handling scenarios

### Performance Tests
- Concurrent session handling
- Audio upload performance
- Database query optimization
- Memory usage monitoring

## Monitoring & Analytics

### Metrics to Track
- Session completion rates
- Average processing times
- Error rates and types
- Audio quality scores
- Student engagement metrics

### Logging
- Session lifecycle events
- Python service communication
- Error tracking and debugging
- Performance monitoring

## Security Considerations

### Data Protection
- Audio file encryption
- Secure file storage
- PII data handling
- GDPR compliance

### Access Control
- Tenant isolation
- Student data privacy
- Service authentication
- Rate limiting

## Deployment Checklist

### Environment Setup
- [ ] JAM_SECRET environment variable
- [ ] Python service URL configuration
- [ ] Database migration execution
- [ ] File storage configuration

### Service Dependencies
- [ ] Python JAM service deployment
- [ ] Audio processing capabilities
- [ ] AI evaluation service
- [ ] File storage service

### Monitoring Setup
- [ ] Logging configuration
- [ ] Metrics collection
- [ ] Error tracking
- [ ] Performance monitoring

## Documentation

### API Documentation
- OpenAPI/Swagger specification
- Request/response examples
- Error code documentation
- Authentication guide

### Developer Guide
- Setup instructions
- Development workflow
- Testing procedures
- Deployment guide

---

## Next Steps

1. Run Migration: Execute the database migration to create the jam_sessions table
2. Configure Environment: Set up JAM_SECRET and PYTHON_BASE_URL
3. Test Backend: Verify all endpoints work correctly
4. Develop Python Service: Implement the JAM service with topic generation and audio processing
5. Frontend Development: Create LiveView interface for JAM sessions
6. Integration Testing: Test end-to-end functionality
7. Production Deployment: Deploy to production environment

The backend foundation is now complete and ready for Python service integration and frontend development.
