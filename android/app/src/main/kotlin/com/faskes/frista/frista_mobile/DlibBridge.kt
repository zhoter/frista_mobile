package com.faskes.frista.frista_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

object DlibBridge {
    private const val TAG = "DlibBridge"
    private var isInitialized = false

    init {
        try {
            System.loadLibrary("frista_dlib")
            Log.i(TAG, "Native library frista_dlib loaded")
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to load native library frista_dlib", e)
        }
    }

    external fun nativeInit(spPath: String, resnetPath: String): Boolean
    external fun nativeComputeDescriptor(
        bitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int
    ): FloatArray?

    fun init(context: Context): Boolean {
        if (isInitialized) return true

        return try {
            val spFile = copyAssetToFile(context, "shape_predictor_5_face_landmarks.dat")
            val resnetFile = copyAssetToFile(context, "dlib_face_recognition_resnet_model_v1.dat")

            if (spFile != null && resnetFile != null) {
                isInitialized = nativeInit(spFile.absolutePath, resnetFile.absolutePath)
                Log.i(TAG, "Dlib nativeInit result: $isInitialized")
                isInitialized
            } else {
                Log.e(TAG, "Could not find model files in assets")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing DlibBridge", e)
            false
        }
    }

    fun computeDescriptorFromBytes(
        jpegBytes: ByteArray,
        left: Int = 0,
        top: Int = 0,
        right: Int = 0,
        bottom: Int = 0
    ): FloatArray? {
        val originalBitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size) ?: return null

        // 1. Determine rotation from EXIF
        var rotation = 0f
        try {
            val exif = ExifInterface(ByteArrayInputStream(jpegBytes))
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            rotation = when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            Log.i(TAG, "EXIF Orientation: $orientation, rotation angle: $rotation")
        } catch (e: Exception) {
            Log.w(TAG, "Could not read EXIF orientation: ${e.message}")
        }

        // 2. Scale down if image is too large (> 1024px) for faster landmark calculation
        val maxDim = max(originalBitmap.width, originalBitmap.height)
        val scale = if (maxDim > 1024) 1024f / maxDim else 1f

        var workingBitmap = originalBitmap
        if (rotation != 0f || scale != 1f) {
            val matrix = Matrix()
            if (scale != 1f) {
                matrix.postScale(scale, scale)
            }
            if (rotation != 0f) {
                matrix.postRotate(rotation)
            }
            workingBitmap = Bitmap.createBitmap(
                originalBitmap,
                0,
                0,
                originalBitmap.width,
                originalBitmap.height,
                matrix,
                true
            )
            if (workingBitmap != originalBitmap) {
                originalBitmap.recycle()
            }
        }

        // 3. Try compute descriptor in detected orientation
        var result = nativeComputeDescriptor(workingBitmap, left, top, right, bottom)

        // 4. Fallback: if face not found, try all other 3 rotations (90, 180, 270)
        if (result == null) {
            Log.i(TAG, "No face found at initial orientation, testing fallback rotations...")
            val fallbackAngles = listOf(90f, 180f, 270f)
            for (angle in fallbackAngles) {
                val rotateMatrix = Matrix().apply { postRotate(angle) }
                val rotated = Bitmap.createBitmap(
                    workingBitmap,
                    0,
                    0,
                    workingBitmap.width,
                    workingBitmap.height,
                    rotateMatrix,
                    true
                )
                result = nativeComputeDescriptor(rotated, 0, 0, 0, 0)
                rotated.recycle()
                if (result != null) {
                    Log.i(TAG, "Face successfully detected and descriptor extracted at fallback rotation: $angle deg!")
                    break
                }
            }
        }

        workingBitmap.recycle()
        return result
    }

    private fun copyAssetToFile(context: Context, assetName: String): File? {
        val outFile = File(context.filesDir, assetName)
        if (outFile.exists() && outFile.length() > 0) {
            return outFile
        }

        return try {
            context.assets.open(assetName).use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            }
            outFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy asset: $assetName", e)
            null
        }
    }
}
