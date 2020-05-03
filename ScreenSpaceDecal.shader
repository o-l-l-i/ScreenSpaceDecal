// Screen Space Decal Shader by Olli S.
Shader "Custom/ScreenSpaceDecal"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", color) = (1,1,1,1)
        _CutOff ("CutOff Threshold", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags { "RenderType"= "Transparent" "Queue" = "Transparent" }
        LOD 100

        Pass
        {
            ZWrite Off
            ZTest Off
            Cull Front

            // Alpha blending
            Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "UnityCG.cginc"


            struct appdata
            {
                float4 vertex : POSITION;
                float3 uv : TEXCOORD0;
            };


            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD1;
                float4 viewRay : TEXCOORD2;
            };


            sampler2D _MainTex;
            float4 _MainTex_ST;

            sampler2D _CameraDepthTexture;
            float4 _CameraDepthTexture_TexelSize;

            float4 _Color;
            float _CutOff;

            // Screen Space Decals a la War Hammer 40k Space Marine
            // https://www.slideshare.net/blindrenderer/screen-space-decals-in-warhammer-40000-space-marine-14699854
            // 1. Draw underlying geometry
            // 2. Rasterize a SSD box
            // 3. Read the scene depth of each pixel
            // 4. Calculate 3D position from depth
            // 5. If the position is outside of the SSD box, reject
            // 6. Otherwise, draw the pixel with the decal texture

            v2f vert (appdata v)
            {
                v2f o;

                // Regular object UVs
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                // CLIP SPACE / PROJECTION POSITION
                // Manual:
                // float4 UnityObjectToClipPos(float3 pos):
                // Transforms a point from object space to the camera’s clip space in homogeneous coordinates
                // This is the equivalent of mul(UNITY_MATRIX_MVP, float4(pos, 1.0)) and should be used in its place
                o.vertex = UnityObjectToClipPos(v.vertex.xyz);

                // SCREEN SPACE POSITION
                // Manual:
                // float4 ComputeScreenPos (float4 clipPos)	Computes texture coordinate for doing a screenspace-mapped texture sample
                // Input is clip space position
                // https://forum.unity.com/threads/what-does-the-function-computescreenpos-in-unitycg-cginc-do.294470/
                o.screenPos = ComputeScreenPos(o.vertex);

                // VIEW / CAMERA SPACE POSITION
                // Camera centered coordinate system
                float3 viewPos = UnityObjectToViewPos(v.vertex);

                // WORLD POSITION
                // Vertex position in the world space
                float4 worldPos = mul(unity_ObjectToWorld, v.vertex);

                // VIEW RAY
                // Camera to vertex ray (also later in texel camera to texel)
                // Should be from camera to the vertex, but in view/camera space?
                // Create a view direction by multiplying view position by far plane
                float3 viewRay = viewPos.xyz * _ProjectionParams.z;
                // Or by first creating a world ray, and then transforming it to the view space
                // float3 worldRay = worldPos.xyz - _WorldSpaceCameraPos.xyz;
                // float3 viewRay = mul(UNITY_MATRIX_V, worldRay) * _ProjectionParams.z;

                // Flip x and y-axis, becaus of Unity's right hand(?) coordinates
                viewRay *= float3(-1,-1, 1);

                // Perform a divide by the view position z in the fragment shader
                // Otherwise coordinates will be all wrong
                o.viewRay.xyzw = float4(viewRay.xyz, viewPos.z);

                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }


            fixed4 frag (v2f i) : SV_Target
            {
                // SCREEN SPACE POSITION
                // Remember to divide with w
                // https://forum.unity.com/threads/what-does-the-function-computescreenpos-in-unitycg-cginc-do.294470/
                float2 screenUV = i.screenPos.xy / i.screenPos.w;

                // DEPTH
                // Sample depth using screen UVs
                // Linearize, remap to 0-1 range
                float depth = Linear01Depth(tex2D(_CameraDepthTexture, screenUV));

                // VIEW RAY
                // Divide viewRay by the stored view position z
                float3 viewRay = i.viewRay.xyz / i.viewRay.w;

                // DECAL PROJECTION POSITION
                // Scale the view ray to texel depth:
                // View space is 0-1, depth is 0-1, by multiplying the view ray position, we move it to the depth distance
                // So we get position we see in the world, and not on the decal projector object's surface
                float4 decalProjectionPos = float4(viewRay.xyz * depth, 1);

                // TRANSFORM FROM VIEW TO WORLD SPACE
                // Now transform the projection position from view/camera space to the world space
                float3 worldSpacePos = mul(unity_CameraToWorld, decalProjectionPos).xyz;

                // TRANSFORM FROM WORLD TO OBJECT SPACE
                // Then transfer the surface hit world space position to the object's space
                float3 objectPos = mul(unity_WorldToObject, float4(worldSpacePos, 1)).xyz;

                // APPLY CUT OFF
                // Apply stretching and backface cut off to avoid decal streaks
                float sideStrechThreshold = 0.999 - _CutOff;

                // NORMALS
                // Calculate normals from screen space derivatives
                // https://forum.unity.com/threads/flat-lighting-without-separate-smoothing-groups.280183/
                float3 objectSpaceNormal = normalize(cross(ddx(objectPos), ddy(objectPos)));

                // MASK
                // Generate a mask from the derived normal
                float mask = objectSpaceNormal.y > sideStrechThreshold ? 1.0 : 0.0;

                // CLIP
                // Remove all non-decal area texels, using also masking
                clip(0.5 * mask - abs(objectPos.xyz));

                // DECAL-SPACE UVs
                // Generate UVs in decal object's space, using decal xz-plane as the projector plane:
                float2 decalUV = objectPos.xz + 0.5;
                       // Apply Unity texture tiling and offset
                       decalUV.xy * _MainTex_ST.xy + _MainTex_ST.zw;

                // SAMPLE DECAL TEXTURE
                // Also apply the Inspector color
                float4 col = tex2D(_MainTex, decalUV) * _Color;

                // Apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
            }
            ENDCG

        }
    }
}
