Shader "Custom/ApplyFogToScene"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}			// The main texture to be computed
	}
	
	CGINCLUDE
            #include "UnityCG.cginc"      
             
			// Vertex data structure
            struct v2f 
            {
				float4 pos : SV_POSITION;		// Vertex position in 3D scene coordinates
				float2 uv : TEXCOORD0;			// First uv coordinate
            };   
			

            uniform sampler2D FogRenderTexture,			// The fog texture to be applied
                              _CameraDepthTexture,		// Depth map for the current camera
                              _MainTex;					// Main texture to be calculated/rendered
            
            uniform float4    _CameraDepthTexture_TexelSize,	// Dimensions of depth texture map
                              _MainTex_TexelSize;				// Dimensions of main texture
            
            
            uniform float4x4  InverseViewMatrix,		// Camera-to-World matrix
							  InverseProjectionMatrix;	// Inverse of the current camera matrix                  
            
			// Vertex Shader
            v2f vert(appdata_img v ) 
            {
				v2f o; 										// Current vertex
				o.pos = UnityObjectToClipPos(v.vertex); 	// World C.S. to Normalized C.S.
				o.uv = v.texcoord;							// Current position in texture (0 to 1)

				return o;									// The modified vertex data structure
            }
            
			
			// Fragment Shader (Input is a vertex from the vertex shader)
            float4 frag(v2f input) : SV_Target	// SV_Target semantic: Output is a pixel color
            {			

                float4 fogSample = tex2D(FogRenderTexture, input.uv);	// Per-Pixel Fog Color Values
                float4 colorSample = tex2D(_MainTex, input.uv);			// Per-Pixel Scene Color Values
                
				float4 result = float4(colorSample.rgb * (1 - fogSample.a) + fogSample.rgb * fogSample.a, colorSample.a);
				
				// DEBUG: Display fog calculation only
				// float4 result = float4(fogSample.rgb * fogSample.a, 1.0f);

				return result;
            }
			                 
	ENDCG
	SubShader
	{
		// No culling or depth writes
		Cull Off ZWrite Off ZTest Always
        
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			ENDCG
		}
		
	}
}
