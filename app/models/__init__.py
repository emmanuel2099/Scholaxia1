# models — import all so SQLAlchemy registers them with Base.metadata
from app.models.user import User, StudentProfile, TeacherProfile, VendorProfile, KindProfile
from app.models.payment import Subscription, Payment, StudentEntitlement
from app.models.cbt import CBTExam, CBTQuestion, CBTSession, ExamProctorLog
from app.models.community import CommunityChannel, CommunityMessage, AssignmentSubmission, MessageReport, CommunityPost, PostLike, PostReaction
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest
from app.models.content import Book, BookPurchase, SavedBook, BookReadProgress, Video, Note, Syllabus, BookRecommendation
from app.models.marketplace import (
    MarketplaceProduct,
    MarketplaceBooking,
    MarketplaceCartItem,
    MarketplaceOrder,
    MarketplaceOrderItem,
    VendorWithdrawalRequest,
)
from app.models.kid_games import KidGameQuestion
from app.models.notification import Notification
from app.models.school_group import SchoolGroup
from app.models.live_class_access_code import LiveClassAccessCodeDelivery
from app.models.student_group import StudentGroup, StudentGroupMember, StudentGroupJoinRequest, StudentGroupMessage
from app.models.sia_note import SiaNote
from app.models.api_key import ApiKey, ApiUsageLog, ApiDailyUsage
from app.models.review_report import Report, TeacherReview
from app.models.wallet import TeacherWallet, WalletTransaction, WithdrawalRequest
from app.models.student_analytics import StudentLearningProfile, LessonSession
from app.models.sil import (
    SilLeagueProfile,
    SilCoinTransaction,
    SilQuestion,
    SilMatch,
    SilChallengeInvite,
    SilSchoolProfile,
    SilAntiCheatEvent,
    SilFlaggedMatch,
    SilDeviceReport,
)
