'use client';

import Link from 'next/link';
import { motion, AnimatePresence } from 'framer-motion';
import { Lock, X, ArrowRight } from 'lucide-react';

export interface AuthGateModalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  message?: string;
}

export function AuthGateModal({ 
  isOpen, 
  onClose, 
  title = "Access Restricted", 
  message = "You need to log in or create an account to access this area. Join the eSportlyic community to continue!" 
}: AuthGateModalProps) {
  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center px-4 py-6">
          {/* Backdrop */}
          <motion.div 
            initial={{ opacity: 0 }} 
            animate={{ opacity: 1 }} 
            exit={{ opacity: 0 }} 
            onClick={onClose}
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
          />
          
          {/* Modal Content */}
          <motion.div 
            initial={{ scale: 0.95, opacity: 0, y: 20 }}
            animate={{ scale: 1, opacity: 1, y: 0 }}
            exit={{ scale: 0.95, opacity: 0, y: 20 }}
            className="relative w-full max-w-md bg-[#0F172A] border border-white/10 rounded-[2rem] shadow-2xl p-8 overflow-hidden text-center z-10"
          >
            {/* Modal Glow */}
            <div className="absolute -top-20 -right-20 w-40 h-40 bg-brand-lime/20 rounded-full blur-[60px]" />
            
            <button 
              onClick={onClose}
              className="absolute top-5 right-5 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-400 hover:text-white transition-colors"
            >
              <X className="w-4 h-4" />
            </button>

            <div className="w-16 h-16 mx-auto bg-brand-lime/10 border border-brand-lime/20 rounded-2xl flex items-center justify-center mb-6">
              <Lock className="w-8 h-8 text-brand-lime" />
            </div>

            <h2 className="text-2xl font-black text-white tracking-tight mb-3">
              {title}
            </h2>
            <p className="text-sm text-slate-400 font-medium mb-8 leading-relaxed px-4">
              {message}
            </p>

            <div className="flex flex-col gap-3">
              <Link 
                href="/login" 
                className="w-full py-3.5 bg-brand-lime text-slate-900 font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 shadow-lg shadow-brand-lime/20 group"
              >
                Log In or Sign Up
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </Link>
              <button 
                onClick={onClose}
                className="w-full py-3.5 bg-white/5 text-white font-bold rounded-xl hover:bg-white/10 transition-colors"
              >
                Cancel
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
