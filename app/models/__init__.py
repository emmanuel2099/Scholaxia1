# models — import all so SQLAlchemy registers them with Base.metadata
from app.models.user import User, StudentProfile, TeacherProfile, KindProfile
from app.models.payment import Subscription, Payment
from app.models.cbt import CBTExam, CBTQuestion, CBTSession, ExamProctorLog
from app.models.community import CommunityChannel, CommunityMessage, AssignmentSubmission, MessageReport, CommunityPost, PostLike
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest
from app.models.content import Book, SavedBook, BookReadProgress, Video, Note, Syllabus, BookRecommendation
from app.models.notification import Notification
from app.models.sia_note import SiaNote
from app.models.api_key import ApiKey, ApiUsageLog, ApiDailyUsage
from app.models.review_report import Report, TeacherReview
from app.models.wallet import TeacherWallet, WalletTransaction, WithdrawalRequest
from app.models.student_analytics import StudentLearningProfile, LessonSession
