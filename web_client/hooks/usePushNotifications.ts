import { useState, useEffect } from 'react';
import { getMessaging, getToken, onMessage, isSupported } from 'firebase/messaging';
import { doc, updateDoc, arrayUnion } from 'firebase/firestore';
import { app, auth, db } from '@/lib/firebase';

export function usePushNotifications() {
  const [permission, setPermission] = useState<NotificationPermission>('default');
  const [fcmToken, setFcmToken] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (typeof window !== 'undefined' && 'Notification' in window) {
      setPermission(Notification.permission);
      
      // Check if browser supports FCM
      isSupported().then((supported) => {
        setIsReady(supported);
      });
    }
  }, []);

  const requestPermission = async () => {
    if (!isReady || !auth.currentUser) {
      alert("Push notifications are not supported on this browser or you are not logged in.");
      return;
    }

    try {
      const currentPermission = await Notification.requestPermission();
      setPermission(currentPermission);

      if (currentPermission === 'granted') {
        const messaging = getMessaging(app);
        const vapidKey = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY;
        
        if (!vapidKey) throw new Error("VAPID Key is missing in environment variables.");

        // Register Service Worker explicitly
        const registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
        
        const token = await getToken(messaging, {
          vapidKey: vapidKey,
          serviceWorkerRegistration: registration,
        });

        if (token) {
          setFcmToken(token);
          // Save the web token to Firestore under the user's document.
          // In your Flutter app, you might save tokens to an array (e.g., 'fcmTokens')
          const userRef = doc(db, 'users', auth.currentUser.uid);
          await updateDoc(userRef, {
            fcmTokens: arrayUnion(token), // arrayUnion prevents duplicate tokens
            webFcmToken: token // Also store specifically as web token
          });
          
          console.log("FCM Web Token secured and saved!");
        }
      } else {
        alert("Notification permission denied.");
      }
    } catch (error) {
      console.error("Error requesting notification permission:", error);
    }
  };

  // Listen for foreground messages
  useEffect(() => {
    if (isReady && permission === 'granted') {
      const messaging = getMessaging(app);
      const unsubscribe = onMessage(messaging, (payload) => {
        console.log("Received foreground message: ", payload);
        // You could trigger a React Toast notification here!
        if (payload.notification) {
          // Native browser notification as a fallback while tab is open
          new Notification(payload.notification.title || "New Notification", {
            body: payload.notification.body,
          });
        }
      });
      
      return () => unsubscribe();
    }
  }, [isReady, permission]);

  return { permission, fcmToken, requestPermission, isReady };
}
